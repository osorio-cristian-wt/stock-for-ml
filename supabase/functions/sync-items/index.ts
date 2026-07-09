// POST /sync-items   body: { ml_account_id?, drain? }  (app / cron / service-role)
// RF-36: imports a seller's listings into ml_listings in resumable BATCHES.
//
// Modes:
//   · {} or { ml_account_id }  — start (or resume) an import job per account,
//     then process one batch. The app loops this call while the job runs and
//     renders live progress from the returned snapshot / Realtime.
//   · { drain: true }          — cron safety-net: only CONTINUES jobs that are
//     pending/processing (never starts one), e.g. app closed mid-import.
//
// Each invocation processes at most BATCH items (~2 ML calls per item), well
// under the Edge Function wall-clock limit that used to cut ~100-item imports.
import { handlePreflight, jsonResponse } from "../_shared/cors.ts";
import { mlConfig } from "../_shared/env.ts";
import { createAdminClient } from "../_shared/supabaseAdmin.ts";
import { MeliClient } from "../_shared/meli.ts";
import { getValidAccessToken } from "../_shared/credentials.ts";
import { upsertItem } from "../_shared/items.ts";
import { MlAccountRow } from "../_shared/orders.ts";

const BATCH = 15;        // items per invocation
const MAX_ERRORS = 50;   // cap stored per-item errors
// A processing job whose heartbeat (updated_at) is older than this is
// considered abandoned and can be re-claimed (crashed invocation).
const STALE_MS = 2 * 60 * 1000;

interface ImportJobRow {
  id: string;
  profile_id: string;
  ml_account_id: string;
  status: string;
  total: number | null;
  processed: number;
  failed: number;
  last_offset: number;
  errors: string[];
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;

  const admin = createAdminClient();
  const cfg = mlConfig();

  let accountId: string | undefined;
  let drain = false;
  try {
    const body = await req.json();
    accountId = body?.ml_account_id;
    drain = body?.drain === true;
  } catch (_) { /* allow empty body */ }

  // 1) Resolve the jobs to work on.
  const jobs: ImportJobRow[] = [];
  if (drain) {
    const { data } = await admin
      .from("import_jobs")
      .select("*")
      .in("status", ["pending", "processing"])
      .order("started_at", { ascending: true });
    jobs.push(...((data ?? []) as ImportJobRow[]));
  } else {
    const { data: accounts } = await admin
      .from("ml_accounts")
      .select("id, profile_id, ml_user_id")
      .match(accountId ? { id: accountId } : {});
    for (const account of (accounts ?? []) as MlAccountRow[]) {
      // Reuse the active job if one exists (unique partial index guards races).
      const { data: existing } = await admin
        .from("import_jobs")
        .select("*")
        .eq("ml_account_id", account.id)
        .in("status", ["pending", "processing"])
        .maybeSingle();
      if (existing) {
        jobs.push(existing as ImportJobRow);
        continue;
      }
      const { data: created, error } = await admin
        .from("import_jobs")
        .insert({ profile_id: account.profile_id, ml_account_id: account.id })
        .select("*")
        .single();
      if (created) jobs.push(created as ImportJobRow);
      else if (error?.code === "23505") {
        // Lost the race to another invocation: pick up its job.
        const { data: raced } = await admin
          .from("import_jobs")
          .select("*")
          .eq("ml_account_id", account.id)
          .in("status", ["pending", "processing"])
          .maybeSingle();
        if (raced) jobs.push(raced as ImportJobRow);
      }
    }
  }

  // 2) Process one batch per job.
  const snapshots: Record<string, unknown>[] = [];
  for (const job of jobs) {
    snapshots.push(await processJobBatch(admin, cfg.apiBase, cfg.siteId, job));
  }

  return jsonResponse({ jobs: snapshots });
});

async function processJobBatch(
  // deno-lint-ignore no-explicit-any
  admin: any,
  apiBase: string,
  siteId: string,
  job: ImportJobRow,
): Promise<Record<string, unknown>> {
  // Claim the job (optimistic): pending, or processing with a stale heartbeat.
  const staleBefore = new Date(Date.now() - STALE_MS).toISOString();
  const { data: claimed } = await admin
    .from("import_jobs")
    .update({ status: "processing", updated_at: new Date().toISOString() })
    .eq("id", job.id)
    .or(`status.eq.pending,and(status.eq.processing,updated_at.lt.${staleBefore})`)
    .select("*")
    .maybeSingle();
  if (!claimed) {
    // Someone else is actively working this job — report it untouched.
    return jobSnapshot(job);
  }
  const j = claimed as ImportJobRow;

  try {
    const { data: account } = await admin
      .from("ml_accounts")
      .select("id, profile_id, ml_user_id")
      .eq("id", j.ml_account_id)
      .single();
    if (!account) throw new Error("cuenta ML inexistente");

    const token = await getValidAccessToken(admin, account.id);
    const client = new MeliClient(token, apiBase);

    let { total, processed, failed, last_offset: offset } = j;
    const errors: string[] = Array.isArray(j.errors) ? [...j.errors] : [];
    let handled = 0;

    while (handled < BATCH) {
      const page = await client.searchUserItems(
        account.ml_user_id,
        offset,
        Math.min(50, BATCH - handled),
      );
      total = page.paging?.total ?? total ?? 0;
      if (page.results.length === 0) break;

      for (const itemId of page.results) {
        try {
          await upsertItem(admin, account, client, itemId, siteId);
          processed++;
        } catch (e) {
          failed++;
          if (errors.length < MAX_ERRORS) {
            errors.push(`${itemId}: ${e instanceof Error ? e.message : e}`);
          }
        }
        handled++;
      }
      offset += page.results.length;
      if (total != null && offset >= total) break;
    }

    const done = total != null && (offset >= total);
    await admin.from("import_jobs").update({
      status: done ? "done" : "processing",
      total,
      processed,
      failed,
      last_offset: offset,
      errors,
      finished_at: done ? new Date().toISOString() : null,
      updated_at: new Date().toISOString(),
    }).eq("id", j.id);

    return jobSnapshot({ ...j, status: done ? "done" : "processing", total, processed, failed, last_offset: offset, errors });
  } catch (e) {
    // Job-level failure (token, red, cuenta): queda en error y visible en la
    // app; re-lanzar el import crea un job nuevo que retoma (idempotente).
    const msg = String(e instanceof Error ? e.message : e);
    await admin.from("import_jobs").update({
      status: "error",
      errors: [...(Array.isArray(job.errors) ? job.errors : []), msg].slice(0, MAX_ERRORS),
      finished_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", job.id);
    return { ...jobSnapshot(job), status: "error", error: msg };
  }
}

function jobSnapshot(j: ImportJobRow): Record<string, unknown> {
  return {
    id: j.id,
    ml_account_id: j.ml_account_id,
    status: j.status,
    total: j.total,
    processed: j.processed,
    failed: j.failed,
    errors: j.errors ?? [],
  };
}
