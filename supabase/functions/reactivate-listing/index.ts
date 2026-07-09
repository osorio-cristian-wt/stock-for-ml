// POST /reactivate-listing  (Authorization: Bearer <app user JWT>)
// RF-47/RF-48: sets a publication's status from the app. Default "active"
// (reactivate a paused_by_seller listing after stock came back); "paused"
// pauses it. Out-of-stock pauses do NOT need this — the regular stock push
// (PUT available_quantity > 0) already reactivates those per ML docs. Body:
//   { ml_item_ids: ["MLA123", ...], status?: "active" | "paused" }
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient, getUserFromJwt } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { upsertItem } from "../_shared/items.ts";
import { MlAccountRow } from "../_shared/orders.ts";

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!jwt) return jsonResponse({ error: "missing bearer token" }, 401);
    const user = await getUserFromJwt(jwt);
    if (!user) return jsonResponse({ error: "invalid token" }, 401);

    const body = await req.json().catch(() => ({})) as {
      ml_item_ids?: string[];
      status?: string;
    };
    const ids = (body.ml_item_ids ?? [])
      .map((s) => String(s).trim().toUpperCase())
      .filter((s) => s.length > 0);
    if (ids.length === 0) return jsonResponse({ error: "ml_item_ids required" }, 400);
    const status = body.status ?? "active";
    if (status !== "active" && status !== "paused") {
      return jsonResponse({ error: "status must be active or paused" }, 400);
    }

    const admin = createAdminClient();
    const cfg = mlConfig();
    const { data: account } = await admin
      .from("ml_accounts")
      .select("id, profile_id, ml_user_id")
      .eq("profile_id", user.id)
      .order("connected_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!account) return jsonResponse({ error: "no ML account linked" }, 400);

    const token = await getValidAccessToken(admin, account.id);
    const client = new MeliClient(token, cfg.apiBase);

    let updated = 0;
    const errors: string[] = [];
    for (const itemId of ids) {
      try {
        // Ownership: only listings mirrored for this profile can be touched.
        const { data: listing } = await admin
          .from("ml_listings")
          .select("id")
          .eq("profile_id", account.profile_id)
          .eq("ml_item_id", itemId)
          .maybeSingle();
        if (!listing) throw new Error("publicación no encontrada");
        await client.updateItemStatus(itemId, status);
        // Refresh the mirror so the app sees the new status right away.
        await upsertItem(admin, account as MlAccountRow, client, itemId, cfg.siteId);
        updated++;
      } catch (e) {
        errors.push(`${itemId}: ${e instanceof Error ? e.message : e}`);
      }
    }

    return jsonResponse({ updated, errors });
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500);
  }
});
