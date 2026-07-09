-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 25 · RF-36 — Import de publicaciones por lotes con progreso         ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Antes sync-items recorría TODAS las publicaciones en una sola invocación:
-- con ~100 ítems superaba el límite de la Edge Function y el import "se
-- cortaba" sin feedback (aunque re-importar es idempotente y retoma).
-- Ahora cada import es un job persistente que se procesa por lotes: lo drena
-- la app mientras está abierta (loop de invocaciones, progreso en vivo) y el
-- cron cada minuto como red de seguridad si la app se cierra a mitad.

create table public.import_jobs (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  ml_account_id uuid not null references public.ml_accounts(id) on delete cascade,
  status        public.ml_event_status not null default 'pending',
  -- total de publicaciones reportado por ML (paging.total de la 1ª página).
  total         int,
  processed     int not null default 0,
  failed        int not null default 0,
  last_offset   int not null default 0,
  -- Primeros errores por ítem (capado en la Edge Function para no crecer sin límite).
  errors        jsonb not null default '[]'::jsonb,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  updated_at    timestamptz not null default now()
);
comment on table public.import_jobs is
  'RF-36: jobs de import de publicaciones ML, procesados por lotes (app + cron). updated_at hace de heartbeat del lote en curso.';

-- Un solo import activo por cuenta ML.
create unique index import_jobs_one_active_idx
  on public.import_jobs (ml_account_id)
  where status in ('pending', 'processing');
create index import_jobs_profile_idx
  on public.import_jobs (profile_id, started_at desc);

-- La app solo LEE el progreso; los jobs los escribe la Edge Function
-- (service_role bypasea RLS).
alter table public.import_jobs enable row level security;
create policy "import_jobs owner read" on public.import_jobs
  for select to authenticated
  using (profile_id = (select auth.uid()));

-- Progreso en vivo en la app vía Realtime (mismo patrón que la migración 10).
alter table public.import_jobs replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'import_jobs'
  ) then
    alter publication supabase_realtime add table public.import_jobs;
  end if;
end $$;
