-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 15 · listing_variations en realtime (RF-07)                        ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- upsertItem ahora refleja las variaciones de una publicación (talle/color/…)
-- en listing_variations, y el detalle de producto las muestra vía `.stream()`.
-- Igual que en 20260619120001: la tabla debe estar en la publicación
-- `supabase_realtime`, con REPLICA IDENTITY FULL para que la policy RLS por
-- profile_id pueda autorizar UPDATE/DELETE.

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
begin
  alter table public.listing_variations replica identity full;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'listing_variations'
  ) then
    alter publication supabase_realtime add table public.listing_variations;
  end if;
end $$;
