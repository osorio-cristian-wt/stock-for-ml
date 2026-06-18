// POST /ml-webhook  (public endpoint configured in the ML application)
// ML posts notifications here. We validate minimally, ENQUEUE into ml_events
// and return 200 fast (ML expects a quick ack and retries otherwise).
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";

interface MlNotification {
  resource: string;
  user_id: number;
  topic: string;
  application_id: number;
  attempts?: number;
  sent?: string;
  received?: string;
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  try {
    const body = await req.json() as MlNotification;
    if (!body?.resource || !body?.topic) {
      return jsonResponse({ error: "invalid notification" }, 400);
    }

    const admin = createAdminClient();
    const { error } = await admin.from("ml_events").insert({
      topic: body.topic,
      resource: body.resource,
      ml_user_id: body.user_id ?? null,
      application_id: body.application_id ?? null,
      attempts: body.attempts ?? 0,
      payload: body as unknown as Record<string, unknown>,
    });
    if (error) throw new Error(error.message);

    // Ack fast. Processing happens in process-events (cron / async).
    return jsonResponse({ ok: true });
  } catch (e) {
    // Still return 200-ish? No: a 500 makes ML retry, which is desirable here.
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
