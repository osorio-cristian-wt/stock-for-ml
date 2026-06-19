// POST /classify-product  (Authorization: Bearer <app user JWT>)
// LLM fallback classifier (LAST resort — used only when the ML catalog/predictor
// could not classify). Returns { category_slug, brand, confidence } with the
// model constrained to the caller's category slugs via structured outputs.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { anthropicConfig, supabaseConfig } from "../_shared/env.ts";

interface ClassifyRequest {
  title?: string;
  description?: string;
  category_slugs?: string[];
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  try {
    // Authenticated app user only (this calls a paid API behind the backend).
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!jwt) return jsonResponse({ error: "missing bearer token" }, 401);
    const { url } = supabaseConfig();
    const anon = createClient(url, jwt, { auth: { persistSession: false } });
    const { data: userData, error: userErr } = await anon.auth.getUser(jwt);
    if (userErr || !userData?.user) return jsonResponse({ error: "invalid token" }, 401);

    const body = await req.json().catch(() => ({})) as ClassifyRequest;
    const title = (body.title ?? "").trim();
    if (!title) return jsonResponse({ error: "title required" }, 400);
    const slugs = Array.from(new Set([...(body.category_slugs ?? []), "otros"]));

    const cfg = anthropicConfig();
    const res = await fetch(`${cfg.apiBase}/v1/messages`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": cfg.apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: cfg.model,
        max_tokens: 256,
        system:
          "Clasificás productos de e-commerce (MercadoLibre Argentina). Elegí la " +
          "categoría más adecuada de la lista y extraé la marca del título. Si " +
          "ninguna categoría encaja, devolvé category_slug = \"otros\".",
        messages: [{
          role: "user",
          content: `Título: ${title}\nDescripción: ${body.description ?? "-"}`,
        }],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                category_slug: { type: "string", enum: slugs },
                brand: { type: "string" },
                confidence: { type: "number" },
              },
              required: ["category_slug", "brand", "confidence"],
              additionalProperties: false,
            },
          },
        },
      }),
    });

    if (!res.ok) {
      return jsonResponse({ error: `anthropic ${res.status}: ${await res.text()}` }, 502);
    }
    const data = await res.json() as { content?: { type: string; text?: string }[] };
    const text = data.content?.find((b) => b.type === "text")?.text ?? "{}";
    const parsed = JSON.parse(text) as Record<string, unknown>;
    return jsonResponse({ source: "llm", ...parsed });
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
