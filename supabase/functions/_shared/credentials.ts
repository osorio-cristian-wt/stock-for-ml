// Token storage + auto-refresh for ML credentials.
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MeliTokens, refreshAccessToken } from "./meli.ts";
import { mlConfig } from "./env.ts";

export function expiresAtFromNow(expiresInSeconds: number): string {
  return new Date(Date.now() + expiresInSeconds * 1000).toISOString();
}

/** Persist a fresh token pair for an ML account. */
export async function saveTokens(
  admin: SupabaseClient,
  mlAccountId: string,
  tokens: MeliTokens,
): Promise<void> {
  const { error } = await admin.from("ml_credentials").upsert({
    ml_account_id: mlAccountId,
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    token_type: tokens.token_type ?? "bearer",
    scope: tokens.scope ?? null,
    expires_at: expiresAtFromNow(tokens.expires_in),
    updated_at: new Date().toISOString(),
  });
  if (error) throw new Error(`saveTokens: ${error.message}`);
}

/**
 * Returns a valid access token for the account, refreshing (and rotating the
 * single-use refresh token) when it is within `skewSeconds` of expiring.
 */
export async function getValidAccessToken(
  admin: SupabaseClient,
  mlAccountId: string,
  skewSeconds = 600,
): Promise<string> {
  const { data, error } = await admin
    .from("ml_credentials")
    .select("access_token, refresh_token, expires_at")
    .eq("ml_account_id", mlAccountId)
    .single();
  if (error || !data) throw new Error(`No credentials for account ${mlAccountId}`);

  const expMs = new Date(data.expires_at).getTime();
  if (expMs - Date.now() > skewSeconds * 1000) {
    return data.access_token;
  }

  const cfg = mlConfig();
  const tokens = await refreshAccessToken({
    apiBase: cfg.apiBase,
    clientId: cfg.clientId,
    clientSecret: cfg.clientSecret,
    refreshToken: data.refresh_token,
  });
  await saveTokens(admin, mlAccountId, tokens);
  return tokens.access_token;
}
