-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 26 · RF-36 — Cron de drenado de import_jobs                         ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Redefine register_ml_cron_jobs agregando ml-sync-items-drain: cada minuto
-- POST /sync-items {"drain": true} — SOLO continúa jobs pendientes/en curso
-- (nunca inicia imports; iniciarlos es acción de la app). Red de seguridad si
-- la app se cierra a mitad del import.

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

  perform cron.unschedule(jobname) from cron.job
    where jobname in ('ml-refresh-tokens', 'ml-fx-rates', 'ml-process-events',
                      'ml-sync-orders', 'ml-push-stock', 'ml-sync-items-drain');

  -- Refresh ML access tokens hourly (token TTL is 6h; threshold 75 min).
  perform cron.schedule('ml-refresh-tokens', '0 * * * *', format($cmd$
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

  -- Push user/system stock changes to ML every minute (anti-loop: ML events excluded).
  perform cron.schedule('ml-push-stock', '* * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/push-stock', v_key));

  -- Continue in-flight publication imports every minute (RF-36).
  perform cron.schedule('ml-sync-items-drain', '* * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{"drain": true}'::jsonb
    );
  $cmd$, v_base || '/sync-items', v_key));
end;
$$;

revoke all on function private.register_ml_cron_jobs() from public, anon, authenticated;

-- Re-registrar en el apply si el entorno ya está configurado (patrón de la
-- migración 20260703211509).
do $$
begin
  if exists (
    select 1 from private.app_config
    where key = 'functions_base_url' and nullif(value, '') is not null
  )
  and exists (
    select 1 from private.app_config
    where key = 'service_role_key' and nullif(value, '') is not null
  ) then
    perform private.register_ml_cron_jobs();
  else
    raise notice 'Skipping private.register_ml_cron_jobs(): missing private.app_config keys';
  end if;
end
$$;
