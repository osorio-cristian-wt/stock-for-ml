// POST /refresh-tokens  (cron, service-role)
// Refreshes every ML token expiring within the next 75 minutes, rotating
// refresh tokens. The cron runs hourly, so the threshold must exceed the
// interval or a token could expire between two runs.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { refreshAccessToken } from "../_shared/meli.ts";
import { saveTokens } from "../_shared/credentials.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const admin = createAdminClient();
  const cfg = mlConfig();
  const threshold = new Date(Date.now() + 75 * 60 * 1000).toISOString();

  const { data: rows, error } = await admin
    .from("ml_credentials")
    .select("ml_account_id, refresh_token, expires_at")
    .lt("expires_at", threshold);
  if (error) return jsonResponse({ error: error.message }, 500);

  let refreshed = 0;
  const failures: string[] = [];
  for (const row of rows ?? []) {
    try {
      const tokens = await refreshAccessToken({
        apiBase: cfg.apiBase,
        clientId: cfg.clientId,
        clientSecret: cfg.clientSecret,
        refreshToken: row.refresh_token,
      });
      await saveTokens(admin, row.ml_account_id, tokens);
      refreshed++;
    } catch (e) {
      failures.push(`${row.ml_account_id}: ${e instanceof Error ? e.message : e}`);
    }
  }

  return jsonResponse({ checked: rows?.length ?? 0, refreshed, failures });
});
