// GET /oauth-url  (Authorization: Bearer <app user JWT>)
// Returns the ML authorization URL and persists the PKCE state for callback.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient, getUserFromJwt } from "../_shared/supabaseAdmin.ts";
import { buildAuthorizeUrl } from "../_shared/meli.ts";
import { generatePkce, randomString } from "../_shared/pkce.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");
    if (!jwt) return jsonResponse({ error: "missing bearer token" }, 401);

    // Resolve the app user from their JWT.
    const user = await getUserFromJwt(jwt);
    if (!user) return jsonResponse({ error: "invalid token" }, 401);

    const cfg = mlConfig();
    const state = randomString(24);
    const pkce = await generatePkce();

    const admin = createAdminClient();
    const { error } = await admin.from("oauth_states").insert({
      state,
      profile_id: user.id,
      code_verifier: pkce.codeVerifier,
      redirect_uri: cfg.redirectUri,
    });
    if (error) throw new Error(error.message);

    const authorizeUrl = buildAuthorizeUrl({
      authBase: cfg.authBase,
      clientId: cfg.clientId,
      redirectUri: cfg.redirectUri,
      state,
      codeChallenge: pkce.codeChallenge,
    });

    return jsonResponse({ authorize_url: authorizeUrl, state });
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
