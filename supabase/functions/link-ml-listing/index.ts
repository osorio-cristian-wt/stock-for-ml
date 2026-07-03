// POST /link-ml-listing  (Authorization: Bearer <app user JWT>)
// Links an EXISTING MercadoLibre publication to an internal stock product.
// Read-only ML access (GET /items) — no write scope required. The listing's
// title stays independent from the product's stock title. Body:
//   { product_id, ml_item_id }
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient, getUserFromJwt } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { upsertItem } from "../_shared/items.ts";
import { MlAccountRow } from "../_shared/orders.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!jwt) return jsonResponse({ error: "missing bearer token" }, 401);
    const user = await getUserFromJwt(jwt);
    if (!user) return jsonResponse({ error: "invalid token" }, 401);
    const userId = user.id;

    const { url, serviceRoleKey } = supabaseConfig();
    const anon = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });

    const body = await req.json().catch(() => ({})) as {
      product_id?: string;
      ml_item_id?: string;
    };
    const productId = (body.product_id ?? "").trim();
    const mlItemId = (body.ml_item_id ?? "").trim().toUpperCase();
    if (!productId || !mlItemId) {
      return jsonResponse({ error: "product_id and ml_item_id required" }, 400);
    }

    // Ownership check via RLS (anon client is scoped to the user).
    const { data: prod } = await anon
      .from("products").select("id").eq("id", productId).maybeSingle();
    if (!prod) return jsonResponse({ error: "product not found" }, 404);

    const admin = createAdminClient();
    const cfg = mlConfig();
    const { data: account } = await admin
      .from("ml_accounts")
      .select("id, profile_id, ml_user_id")
      .eq("profile_id", userId)
      .order("connected_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!account) return jsonResponse({ error: "no ML account linked" }, 400);

    const token = await getValidAccessToken(admin, account.id);
    const client = new MeliClient(token, cfg.apiBase);
    await upsertItem(admin, account as MlAccountRow, client, mlItemId, cfg.siteId, productId);

    return jsonResponse({ ok: true, product_id: productId, ml_item_id: mlItemId });
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
