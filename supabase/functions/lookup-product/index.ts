// POST /lookup-product  (Authorization: Bearer <app user JWT>)
// Barcode-first enrichment: given a GTIN (and/or title), resolve product data
// from the ML catalog, falling back to ML's category predictor. The LLM
// (classify-product) is a separate, last-resort fallback the app calls only if
// this returns source:"none".
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient, getUserFromJwt } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { enrichByGtin, predictCategory, ProductEnrichment } from "../_shared/catalog.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!jwt) return jsonResponse({ error: "missing bearer token" }, 401);

    const user = await getUserFromJwt(jwt);
    if (!user) return jsonResponse({ error: "invalid token" }, 401);
    const profileId = user.id;

    const body = await req.json().catch(() => ({})) as { gtin?: string; title?: string };
    const gtin = (body.gtin ?? "").trim();
    const title = (body.title ?? "").trim();
    if (!gtin && !title) return jsonResponse({ error: "gtin or title required" }, 400);

    const cfg = mlConfig();
    const admin = createAdminClient();
    const { data: account } = await admin
      .from("ml_accounts").select("id").eq("profile_id", profileId).maybeSingle();
    if (!account) return jsonResponse({ error: "no linked ML account" }, 409);

    const token = await getValidAccessToken(admin, account.id);
    const client = new MeliClient(token, cfg.apiBase);

    let result: ProductEnrichment = { source: "none" };
    if (gtin) result = await enrichByGtin(client, cfg.siteId, gtin);
    if (result.source === "none") {
      const t = title || result.name || "";
      if (t) result = await predictCategory(client, cfg.siteId, t);
    }

    return jsonResponse({ gtin: gtin || null, result });
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
