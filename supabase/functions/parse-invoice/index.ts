// POST /parse-invoice  (Authorization: Bearer <app user JWT>)
// Vision OCR for supplier invoices: takes a base64 image, returns structured
// line items { supplier, date, currency, items[] } for the user to APPROVE in
// the app before a purchase is created. Uses Claude Haiku 4.5 (vision + JSON
// schema). Same Anthropic raw-HTTP pattern as classify-product.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { anthropicConfig, supabaseConfig } from "../_shared/env.ts";

interface ParseInvoiceRequest {
  image_base64?: string;
  mime?: string; // image/png | image/jpeg | image/webp
}

const ALLOWED_MIME = new Set(["image/png", "image/jpeg", "image/webp", "image/gif"]);

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

    const body = await req.json().catch(() => ({})) as ParseInvoiceRequest;
    const image = (body.image_base64 ?? "").trim();
    const mime = (body.mime ?? "image/jpeg").trim();
    if (!image) return jsonResponse({ error: "image_base64 required" }, 400);
    if (!ALLOWED_MIME.has(mime)) return jsonResponse({ error: `unsupported mime: ${mime}` }, 400);

    const cfg = anthropicConfig();
    const res = await fetch(`${cfg.apiBase}/v1/messages`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": cfg.apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 2048,
        system:
          "Extraés el detalle de una factura/remito de compra a un proveedor " +
          "(MercadoLibre Argentina, español). Devolvé las líneas de productos con " +
          "cantidad y costo unitario. Si un dato no aparece, dejalo vacío o en 0. " +
          "No inventes productos que no estén en la imagen.",
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mime, data: image } },
            { type: "text", text: "Extraé el proveedor, la fecha, la moneda y las líneas de la factura." },
          ],
        }],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                supplier: { type: "string" },
                date: { type: "string" },
                currency: { type: "string" },
                items: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      description: { type: "string" },
                      sku: { type: "string" },
                      quantity: { type: "number" },
                      unit_cost: { type: "number" },
                    },
                    required: ["description", "sku", "quantity", "unit_cost"],
                    additionalProperties: false,
                  },
                },
              },
              required: ["supplier", "date", "currency", "items"],
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
