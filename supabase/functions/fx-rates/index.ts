// POST /fx-rates  (cron, service-role)
// Fetches the current USD->ARS rate and caches it in public.fx_rates.
// Default provider: dolarapi.com (blue). Override with FX_PROVIDER_URL.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { optionalEnv } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { DolarApiResponse, mapCasaToKind, pickRate } from "../_shared/fx.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const providerUrl = optionalEnv("FX_PROVIDER_URL") ?? "https://dolarapi.com/v1/dolares/blue";

  try {
    const res = await fetch(providerUrl, { headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error(`FX provider ${res.status}`);
    const data = await res.json() as DolarApiResponse;

    const rate = pickRate(data);
    if (!rate) throw new Error("FX provider returned no rate");

    const admin = createAdminClient();
    const { error } = await admin.from("fx_rates").insert({
      base_currency: "USD",
      quote_currency: "ARS",
      kind: mapCasaToKind(data.casa),
      buy: data.compra ?? null,
      sell: data.venta ?? null,
      rate,
      source: providerUrl,
    });
    if (error) throw new Error(error.message);

    return jsonResponse({ ok: true, kind: mapCasaToKind(data.casa), rate });
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
