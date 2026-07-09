// POST /push-stock  (cron, service-role)
// Drains stock_push_queue: products whose AVAILABLE changed due to user/system
// movements. This is the ONLY place that pushes stock to ML (PUT /items).
// ML-origin movements never enter the queue (anti-loop).
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";

const BATCH = 25;
const MAX_ATTEMPTS = 5;

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const admin = createAdminClient();
  const cfg = mlConfig();

  const { data: rows } = await admin
    .from("stock_push_queue")
    .select("product_id, attempts")
    .eq("status", "pending")
    .order("enqueued_at", { ascending: true })
    .limit(BATCH);

  const tokenCache = new Map<string, string>();
  let pushed = 0, failed = 0;

  for (const row of rows ?? []) {
    await admin.from("stock_push_queue").update({ status: "processing" }).eq("product_id", row.product_id);
    try {
      const { data: product } = await admin
        .from("products")
        .select("id, profile_id, current_stock")
        .eq("id", row.product_id)
        .single();
      if (!product) throw new Error("product not found");

      const { data: account } = await admin
        .from("ml_accounts")
        .select("id")
        .eq("profile_id", product.profile_id)
        .maybeSingle();

      const { data: listings } = await admin
        .from("ml_listings")
        .select("ml_item_id, status, has_variations, logistic_type")
        .eq("product_id", row.product_id);

      // Paused listings MUST receive the PUT too: ML pauses an item when its
      // stock hits 0 (sub_status out_of_stock) and reactivates it alone when a
      // quantity > 0 arrives — skipping them would leave the listing stuck
      // paused forever. Only closed/under_review/etc. are untouchable.
      const active = (listings ?? []).filter(
        (l) => l.ml_item_id && (l.status === "active" || l.status === "paused"),
      );
      // ML rejects an item-level available_quantity on items WITH variations
      // (stock lives per variation there). Until the app tracks stock per
      // variation, skip those instead of retry-looping, and leave a note on
      // the queue row so the skip is visible. Fulfillment items are also
      // skipped: their stock is managed by ML Full (RF-38).
      const simple = active.filter(
        (l) => !l.has_variations && l.logistic_type !== "fulfillment",
      );
      const skipped = active.length - simple.length;

      if (account && simple.length > 0) {
        let token = tokenCache.get(account.id);
        if (!token) {
          token = await getValidAccessToken(admin, account.id);
          tokenCache.set(account.id, token);
        }
        const client = new MeliClient(token, cfg.apiBase);
        const qty = Math.max(product.current_stock ?? 0, 0);
        for (const l of simple) {
          await client.updateItemQuantity(l.ml_item_id as string, qty);
        }
      }

      await admin.from("stock_push_queue").update({
        status: "done",
        processed_at: new Date().toISOString(),
        error: skipped > 0
          ? `${skipped} publicación(es) omitida(s): con variaciones (push por variación no soportado) o Full (stock administrado por ML)`
          : null,
      }).eq("product_id", row.product_id);
      pushed++;
    } catch (e) {
      const attempts = (row.attempts ?? 0) + 1;
      // Retry transient failures on the next tick; give up after MAX_ATTEMPTS.
      await admin.from("stock_push_queue").update({
        status: attempts < MAX_ATTEMPTS ? "pending" : "error",
        attempts,
        error: String(e instanceof Error ? e.message : e),
        processed_at: new Date().toISOString(),
      }).eq("product_id", row.product_id);
      failed++;
    }
  }

  return jsonResponse({ processed: rows?.length ?? 0, pushed, failed });
});
