// POST /sync-items   body: { ml_account_id }  (service-role / cron)
// Imports/refreshes all of a seller's listings into ml_listings.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { upsertItem } from "../_shared/items.ts";
import { MlAccountRow } from "../_shared/orders.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const admin = createAdminClient();
  const cfg = mlConfig();

  let accountId: string | undefined;
  try { accountId = (await req.json())?.ml_account_id; } catch (_) { /* allow empty body */ }

  const { data: accounts } = await admin
    .from("ml_accounts")
    .select("id, profile_id, ml_user_id")
    .match(accountId ? { id: accountId } : {});

  let imported = 0;
  const errors: string[] = [];

  for (const account of (accounts ?? []) as MlAccountRow[]) {
    try {
      const token = await getValidAccessToken(admin, account.id);
      const client = new MeliClient(token, cfg.apiBase);

      let offset = 0;
      while (true) {
        const page = await client.searchUserItems(account.ml_user_id, offset, 50);
        for (const itemId of page.results) {
          try { await upsertItem(admin, account, client, itemId, cfg.siteId); imported++; }
          catch (e) { errors.push(`${itemId}: ${e instanceof Error ? e.message : e}`); }
        }
        offset += page.results.length;
        if (offset >= (page.paging?.total ?? 0) || page.results.length === 0) break;
      }
    } catch (e) {
      errors.push(`account ${account.id}: ${e instanceof Error ? e.message : e}`);
    }
  }

  return jsonResponse({ imported, errors });
});
