import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildAuthorizeUrl } from "../_shared/meli.ts";
import { generatePkce, sha256Base64Url } from "../_shared/pkce.ts";
import { mapCasaToKind, pickRate } from "../_shared/fx.ts";
import { resourceId } from "../_shared/items.ts";

Deno.test("buildAuthorizeUrl includes PKCE + required params", () => {
  const url = buildAuthorizeUrl({
    authBase: "https://auth.mercadolibre.com.ar",
    clientId: "123",
    redirectUri: "https://x.functions.supabase.co/oauth-callback",
    state: "st_abc",
    codeChallenge: "chal",
  });
  const u = new URL(url);
  assertEquals(u.searchParams.get("response_type"), "code");
  assertEquals(u.searchParams.get("client_id"), "123");
  assertEquals(u.searchParams.get("state"), "st_abc");
  assertEquals(u.searchParams.get("code_challenge"), "chal");
  assertEquals(u.searchParams.get("code_challenge_method"), "S256");
  assertStringIncludes(url, "auth.mercadolibre.com.ar/authorization");
});

Deno.test("PKCE: code_challenge is the S256 of the verifier", async () => {
  const { codeVerifier, codeChallenge, method } = await generatePkce();
  assertEquals(method, "S256");
  assertEquals(await sha256Base64Url(codeVerifier), codeChallenge);
  assert(!codeChallenge.includes("=") && !codeChallenge.includes("+") && !codeChallenge.includes("/"));
});

Deno.test("fx mapping + rate selection", () => {
  assertEquals(mapCasaToKind("blue"), "blue");
  assertEquals(mapCasaToKind("bolsa"), "mep");
  assertEquals(mapCasaToKind("unknown"), "blue");
  assertEquals(pickRate({ compra: 1180, venta: 1200 }), 1200);
  assertEquals(pickRate({ compra: 1180 }), 1180);
});

Deno.test("resourceId extracts the trailing id from an ML resource", () => {
  assertEquals(resourceId("/items/MLA123"), "MLA123");
  assertEquals(resourceId("/orders/2000003508419013"), "2000003508419013");
  assertEquals(resourceId("/orders/123/"), "123");
});
