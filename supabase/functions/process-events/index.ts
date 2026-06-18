// POST /process-events  (cron, service-role)
// Drains pending ml_events and applies them (orders -> stock, items -> resync).
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { processOrder, MlAccountRow } from "../_shared/orders.ts";
import { upsertItem, resourceId } from "../_shared/items.ts";

const BATCH = 25;

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const admin = createAdminClient();
  const cfg = mlConfig();

  const { data: events } = await admin
    .from("ml_events")
    .select("*")
    .eq("status", "pending")
    .order("received_at", { ascending: true })
    .limit(BATCH);

  let done = 0, failed = 0;

  for (const ev of events ?? []) {
    await admin.from("ml_events").update({ status: "processing", attempts: ev.attempts + 1 }).eq("id", ev.id);
    try {
      const account = await accountForUser(admin, ev.ml_user_id);
      if (!account) throw new Error(`no linked account for ml_user ${ev.ml_user_id}`);

      const token = await getValidAccessToken(admin, account.id);
      const client = new MeliClient(token, cfg.apiBase);
      const id = resourceId(ev.resource);

      if (ev.topic.startsWith("orders")) {
        const order = await client.getOrder(id);
        await processOrder(admin, account, order, client);
      } else if (ev.topic === "items" || ev.topic === "items_prices") {
        await upsertItem(admin, account, client, id, cfg.siteId);
      }
      // other topics: ignored for now

      await admin.from("ml_events").update({ status: "done", processed_at: new Date().toISOString() }).eq("id", ev.id);
      done++;
    } catch (e) {
      await admin.from("ml_events").update({
        status: "error",
        error: String(e instanceof Error ? e.message : e),
        processed_at: new Date().toISOString(),
      }).eq("id", ev.id);
      failed++;
    }
  }

  return jsonResponse({ processed: events?.length ?? 0, done, failed });
});

async function accountForUser(admin: ReturnType<typeof createAdminClient>, mlUserId: number | null): Promise<MlAccountRow | null> {
  if (mlUserId == null) return null;
  const { data } = await admin
    .from("ml_accounts")
    .select("id, profile_id, ml_user_id")
    .eq("ml_user_id", mlUserId)
    .maybeSingle();
  return data ?? null;
}
