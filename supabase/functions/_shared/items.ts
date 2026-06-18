// Shared item-sync logic: pulls an ML item into ml_listings (+ links/creates a
// product and caches a fee estimate). Used by sync-items and process-events.
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MeliClient, MeliItem } from "./meli.ts";
import { MlAccountRow } from "./orders.ts";

const statusMap: Record<string, string> = {
  active: "active",
  paused: "paused",
  closed: "closed",
  under_review: "under_review",
};

export async function upsertItem(
  admin: SupabaseClient,
  account: MlAccountRow,
  client: MeliClient,
  itemId: string,
  siteId: string,
): Promise<void> {
  const item: MeliItem = await client.getItem(itemId);

  // Ensure a linked internal product exists (ML + internal-stock model).
  const { data: existing } = await admin
    .from("ml_listings")
    .select("id, product_id")
    .eq("profile_id", account.profile_id)
    .eq("ml_item_id", item.id)
    .maybeSingle();

  let productId = existing?.product_id ?? null;
  if (!productId) {
    const { data: prod } = await admin
      .from("products")
      .insert({
        profile_id: account.profile_id,
        title: item.title,
        image_url: item.thumbnail,
        sku: item.id, // default SKU = ML id; user can edit later
      })
      .select("id")
      .single();
    productId = prod?.id ?? null;
  }

  // Best-effort fee estimate.
  let estFee: number | null = null;
  try {
    const prices = await client.getListingPrices(siteId, item.price, item.category_id, item.listing_type_id);
    estFee = prices?.[0]?.sale_fee_amount ?? null;
  } catch (_) { /* fees are best-effort */ }

  await admin.from("ml_listings").upsert({
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
  }, { onConflict: "profile_id,ml_item_id" });
}

/** Extracts the id at the end of an ML resource path, e.g. "/items/MLA123" -> "MLA123". */
export function resourceId(resource: string): string {
  return resource.split("/").filter(Boolean).pop() ?? "";
}
