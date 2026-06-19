// POST /price-comparison  (Authorization: Bearer <app user JWT>)
// Compares one of the seller's published listings against the competition
// inside ML (a must-have of the MVP). The app never calls ML directly; this
// function resolves a valid token server-side and runs the public search.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig, supabaseConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { buildComparison, ListingInfo } from "../_shared/comparison.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!jwt) return jsonResponse({ error: "missing bearer token" }, 401);

    const { url } = supabaseConfig();
    const anon = createClient(url, jwt, { auth: { persistSession: false } });
    const { data: userData, error: userErr } = await anon.auth.getUser(jwt);
    if (userErr || !userData?.user) return jsonResponse({ error: "invalid token" }, 401);
    const profileId = userData.user.id;

    const body = await req.json().catch(() => ({})) as {
      listing_id?: string;
      ml_item_id?: string;
    };
    const listingId = (body.listing_id ?? "").trim();
    if (!listingId && !body.ml_item_id) {
      return jsonResponse({ error: "listing_id or ml_item_id required" }, 400);
    }

    const cfg = mlConfig();
    const admin = createAdminClient();

    // The seller's listing (scoped to the profile; service-role bypasses RLS).
    let q = admin
      .from("ml_listings")
      .select("ml_item_id, title, category_id, price, available_quantity, sold_quantity")
      .eq("profile_id", profileId)
      .limit(1);
    q = listingId ? q.eq("id", listingId) : q.eq("ml_item_id", body.ml_item_id!);
    const { data: listing } = await q.maybeSingle();
    if (!listing) return jsonResponse({ error: "listing not found" }, 404);

    const { data: account } = await admin
      .from("ml_accounts").select("id, ml_user_id").eq("profile_id", profileId).maybeSingle();
    if (!account) return jsonResponse({ error: "no linked ML account" }, 409);

    const token = await getValidAccessToken(admin, account.id);
    const client = new MeliClient(token, cfg.apiBase);

    // Fill in the category from ML if the cached listing lacks it.
    let categoryId: string | undefined = listing.category_id ?? undefined;
    if (!categoryId && listing.ml_item_id) {
      const item = await client.getItem(listing.ml_item_id).catch(() => null);
      categoryId = item?.category_id;
    }

    const { results } = await client.searchListings(cfg.siteId, {
      categoryId,
      q: listing.title ?? undefined,
      limit: 40,
    });

    const info: ListingInfo = {
      ml_item_id: listing.ml_item_id,
      title: listing.title ?? "",
      price: Number(listing.price ?? 0),
      category_id: categoryId ?? null,
      sold_quantity: listing.sold_quantity ?? 0,
      available_quantity: listing.available_quantity ?? 0,
      seller_id: account.ml_user_id ?? null,
    };

    return jsonResponse(buildComparison(info, results));
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
