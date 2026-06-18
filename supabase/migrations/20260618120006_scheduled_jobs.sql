-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 06 · Scheduled jobs infrastructure (pg_cron + pg_net)              ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Cron jobs invoke Edge Functions over HTTP, so they need an environment
-- specific base URL + service-role key. We store those in private.app_config
-- and (re)register the jobs via private.register_ml_cron_jobs() AFTER deploy.
-- Nothing here makes outbound calls at migration time, so `db reset` is safe.

create schema if not exists private;

create table if not exists private.app_config (
  key   text primary key,
  value text
);
comment on table private.app_config is
  'Backend config for scheduled jobs (functions_base_url, service_role_key). Not exposed via API.';

-- Extensions are guarded: if the image lacks them, reset still succeeds.
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron not available, skipping (%).', sqlerrm;
end;
$$;

do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net not available, skipping (%).', sqlerrm;
end;
$$;

-- Registers/refreshes all scheduled jobs. Call manually after configuring
-- private.app_config, e.g.:
--   insert into private.app_config values
--     ('functions_base_url','https://<ref>.supabase.co/functions/v1'),
--     ('service_role_key','<service-role-key>')
--   on conflict (key) do update set value = excluded.value;
--   select private.register_ml_cron_jobs();
create or replace function private.register_ml_cron_jobs()
returns void
language plpgsql
security definer
set search_path = private, public, extensions
as $$
declare
  v_base text;
  v_key  text;
begin
  select value into v_base from private.app_config where key = 'functions_base_url';
  select value into v_key  from private.app_config where key = 'service_role_key';

  if v_base is null or v_key is null then
    raise exception 'Configure functions_base_url and service_role_key in private.app_config first';
  end if;

  -- helper to (re)schedule one function call job
  perform cron.unschedule(jobname) from cron.job
    where jobname in ('ml-refresh-tokens', 'ml-fx-rates', 'ml-process-events', 'ml-sync-orders');

  -- Refresh ML access tokens every 5 hours (token TTL is 6h).
  perform cron.schedule('ml-refresh-tokens', '0 */5 * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/refresh-tokens', v_key));

  -- Refresh FX (dollar) rate every 30 minutes.
  perform cron.schedule('ml-fx-rates', '*/30 * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/fx-rates', v_key));

  -- Drain the webhook event queue every minute.
  perform cron.schedule('ml-process-events', '* * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/process-events', v_key));

  -- Safety-net pull of recent orders every 15 minutes (in case a webhook is missed).
  perform cron.schedule('ml-sync-orders', '*/15 * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/sync-orders', v_key));
end;
$$;

revoke all on function private.register_ml_cron_jobs() from public, anon, authenticated;
