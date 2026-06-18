// POST /sync-orders   (cron, service-role)
// Safety-net pull of recent orders in case a webhook was missed.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { processOrder, MlAccountRow } from "../_shared/orders.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const admin = createAdminClient();
  const cfg = mlConfig();

  const { data: accounts } = await admin
    .from("ml_accounts")
    .select("id, profile_id, ml_user_id");

  let processed = 0;
  const errors: string[] = [];

  for (const account of (accounts ?? []) as MlAccountRow[]) {
    try {
      const token = await getValidAccessToken(admin, account.id);
      const client = new MeliClient(token, cfg.apiBase);
      const { results } = await client.searchOrders(account.ml_user_id, 0, 50);
      for (const order of results ?? []) {
        try { await processOrder(admin, account, order, client); processed++; }
        catch (e) { errors.push(`order ${order.id}: ${e instanceof Error ? e.message : e}`); }
      }
    } catch (e) {
      errors.push(`account ${account.id}: ${e instanceof Error ? e.message : e}`);
    }
  }

  return jsonResponse({ processed, errors });
});
