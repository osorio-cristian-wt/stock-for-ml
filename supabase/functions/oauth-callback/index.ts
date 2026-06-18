// GET /oauth-callback?code=...&state=...
// ML redirects here after the user authorizes. Exchanges the code, stores
// credentials, links the ML account, and deep-links back into the app.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig, optionalEnv } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { exchangeCodeForToken, MeliClient } from "../_shared/meli.ts";
import { saveTokens } from "../_shared/credentials.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const appDeepLink = optionalEnv("APP_BASE_URL") ?? "stockforml://auth-callback";

  if (!code || !state) return jsonResponse({ error: "missing code/state" }, 400);

  try {
    const admin = createAdminClient();

    // Validate + consume the PKCE state.
    const { data: st } = await admin
      .from("oauth_states")
      .select("profile_id, code_verifier, redirect_uri, expires_at")
      .eq("state", state)
      .maybeSingle();
    if (!st) return jsonResponse({ error: "unknown state" }, 400);
    if (new Date(st.expires_at).getTime() < Date.now()) {
      return jsonResponse({ error: "state expired" }, 400);
    }

    const cfg = mlConfig();
    const tokens = await exchangeCodeForToken({
      apiBase: cfg.apiBase,
      clientId: cfg.clientId,
      clientSecret: cfg.clientSecret,
      redirectUri: st.redirect_uri ?? cfg.redirectUri,
      code,
      codeVerifier: st.code_verifier,
    });

    // Identify the ML seller.
    const client = new MeliClient(tokens.access_token, cfg.apiBase);
    const me = await client.getMe();

    const { data: account, error: accErr } = await admin
      .from("ml_accounts")
      .upsert({
        profile_id: st.profile_id,
        ml_user_id: me.id,
        nickname: me.nickname,
        site_id: me.site_id ?? cfg.siteId,
      }, { onConflict: "profile_id,ml_user_id" })
      .select("id")
      .single();
    if (accErr) throw new Error(accErr.message);

    await saveTokens(admin, account.id, tokens);
    await admin.from("oauth_states").delete().eq("state", state);

    // Redirect back into the app.
    return new Response(null, {
      status: 302,
      headers: { Location: `${appDeepLink}?status=success&account=${account.id}` },
    });
  } catch (e) {
    return new Response(null, {
      status: 302,
      headers: {
        Location: `${appDeepLink}?status=error&message=${encodeURIComponent(String(e instanceof Error ? e.message : e))}`,
      },
    });
  }
});
