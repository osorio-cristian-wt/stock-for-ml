// Shared item-sync logic: pulls an ML item into ml_listings (+ links/creates a
// product and caches a fee estimate). Used by sync-items and process-events.
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MeliClient, MeliItem, MeliVariation } from "./meli.ts";
import { MlAccountRow } from "./orders.ts";

const statusMap: Record<string, string> = {
  active: "active",
  paused: "paused",
  closed: "closed",
  under_review: "under_review",
};

/** Quotes a value for a PostgREST filter so `,`/`(`/`)`/`.` inside a SKU or
 * GTIN cannot break the `or=(...)` / `in.(...)` syntax. */
export function pgrestQuote(v: string): string {
  return `"${v.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

/** Maps an item's ML variations to `listing_variations` rows (pure). */
export function variationRows(
  profileId: string,
  listingId: string,
  variations: MeliVariation[] | undefined,
): Record<string, unknown>[] {
  return (variations ?? []).map((v) => ({
    profile_id: profileId,
    ml_listing_id: listingId,
    ml_variation_id: String(v.id),
    attributes: v.attribute_combinations ?? [],
    price: v.price ?? null,
    available_quantity: v.available_quantity ?? 0,
  }));
}

export async function upsertItem(
  admin: SupabaseClient,
  account: MlAccountRow,
  client: MeliClient,
  itemId: string,
  siteId: string,
  forceProductId?: string,
): Promise<void> {
  const item: MeliItem = await client.getItem(itemId);

  // Ensure a linked internal product exists (ML + internal-stock model).
  const { data: existing } = await admin
    .from("ml_listings")
    .select("id, product_id")
    .eq("profile_id", account.profile_id)
    .eq("ml_item_id", item.id)
    .maybeSingle();

  // Caller asked to link this listing to a specific internal product (user
  // pairing an existing publication to a stock item). Force the link and skip
  // dedup/creation/stock seeding — the app stays the source of truth for stock.
  let forcedProductId: string | null = null;
  if (forceProductId) {
    forcedProductId = forceProductId;
    await admin.from("stock_push_queue").upsert(
      {
        product_id: forceProductId,
        status: "pending",
        enqueued_at: new Date().toISOString(),
        processed_at: null,
        error: null,
      },
      { onConflict: "product_id" },
    );
  }

  // First import of this listing: link or create the internal product. Because
  // the app is the source of truth for stock, we ONLY seed stock for brand-new
  // products. If the product already exists (matched by GTIN/SKU) we link the
  // listing and push our local stock to ML instead of pulling ML's number.
  let productId = forcedProductId ?? existing?.product_id ?? null;
  if (!productId) {
    const gtin =
      item.attributes?.find((a) => a.id === "GTIN")?.value_name?.trim() || null;
    const skuField = (item.seller_custom_field ??
      item.attributes?.find((a) => a.id === "SELLER_SKU")?.value_name ?? "").trim();
    const sku = skuField.length > 0 ? skuField : null;

    // Dedup against the internal catalog.
    let matchId: string | null = null;
    const ors: string[] = [];
    if (gtin) ors.push(`gtin.eq.${pgrestQuote(gtin)}`);
    if (sku) ors.push(`sku.eq.${pgrestQuote(sku)}`);
    if (ors.length > 0) {
      const { data: match } = await admin
        .from("products")
        .select("id, gtin")
        .eq("profile_id", account.profile_id)
        .or(ors.join(","))
        .limit(1)
        .maybeSingle();
      matchId = match?.id ?? null;
      if (matchId && gtin && !match?.gtin) {
        await admin.from("products").update({ gtin }).eq("id", matchId);
      }
    }

    if (matchId) {
      // Existing product: keep its stock; push our truth to ML.
      productId = matchId;
      await admin.from("stock_push_queue").upsert(
        {
          product_id: productId,
          status: "pending",
          enqueued_at: new Date().toISOString(),
          processed_at: null,
          error: null,
        },
        { onConflict: "product_id" },
      );
    } else {
      const { data: prod } = await admin
        .from("products")
        .insert({
          profile_id: account.profile_id,
          title: item.title,
          image_url: item.thumbnail,
          sku: sku ?? item.id, // default SKU = ML id; user can edit later
          gtin,
        })
        .select("id")
        .single();
      productId = prod?.id ?? null;

      // Seed stock once, from ML, only for the brand-new product. origin=ml so
      // the trigger does NOT echo it back to ML.
      if (productId && item.available_quantity > 0) {
        await admin.from("stock_movements").insert({
          profile_id: account.profile_id,
          product_id: productId,
          bucket: "on_hand",
          delta: item.available_quantity,
          reason: "initial_sync",
          origin: "ml",
          reference: item.id,
          note: "Stock inicial importado de ML",
        });
      }
    }
  }

  // Best-effort fee estimate.
  let estFee: number | null = null;
  try {
    const prices = await client.getListingPrices(siteId, item.price, item.category_id, item.listing_type_id);
    estFee = prices?.[0]?.sale_fee_amount ?? null;
  } catch (_) { /* fees are best-effort */ }

  const { data: listing } = await admin.from("ml_listings").upsert({
    profile_id: account.profile_id,
    product_id: productId,
    ml_account_id: account.id,
    ml_item_id: item.id,
    title: item.title,
    category_id: item.category_id,
    listing_type_id: item.listing_type_id,
    price: item.price,
    currency_id: item.currency_id,
    available_quantity: item.available_quantity,
    sold_quantity: item.sold_quantity,
    est_sale_fee: estFee,
    status: statusMap[item.status] ?? "inactive",
    permalink: item.permalink,
    thumbnail: item.thumbnail,
    has_variations: (item.variations?.length ?? 0) > 0,
    last_synced_at: new Date().toISOString(),
  }, { onConflict: "profile_id,ml_item_id" }).select("id").single();

  // Mirror the listing's variations (size/color/… each with ML-side stock).
  // Stock truth per variation stays in ML for now: the app surfaces the
  // breakdown but push-stock skips item-level PUTs on variation listings.
  if (listing?.id) {
    const rows = variationRows(account.profile_id, listing.id, item.variations);
    if (rows.length > 0) {
      await admin.from("listing_variations").upsert(rows, {
        onConflict: "ml_listing_id,ml_variation_id",
      });
    }
    // Prune variations ML no longer reports (or all, if none remain).
    let stale = admin.from("listing_variations").delete().eq("ml_listing_id", listing.id);
    if (rows.length > 0) {
      const keep = rows.map((r) => pgrestQuote(String(r.ml_variation_id))).join(",");
      stale = stale.not("ml_variation_id", "in", `(${keep})`);
    }
    await stale;
  }
}

/** Extracts the id at the end of an ML resource path, e.g. "/items/MLA123" -> "MLA123". */
export function resourceId(resource: string): string {
  return resource.split("/").filter(Boolean).pop() ?? "";
}
