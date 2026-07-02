-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 10 · Realtime publication                                          ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- The Flutter app subscribes to `products` via `.stream()` (and will stream
-- ml_listings / sales / alerts). Realtime only delivers postgres_changes for
-- tables that belong to the `supabase_realtime` publication, so without this
-- the app loads an initial snapshot but never sees INSERT/UPDATE/DELETE — which
-- is why creating a product, adjusting stock or editing a product did not show
-- up in the list until a cold reload.
--
-- REPLICA IDENTITY FULL: realtime evaluates the owner RLS policy
-- (profile_id = auth.uid()) against the changed row. With the default replica
-- identity (primary key only) UPDATE/DELETE payloads omit `profile_id`, so the
-- policy cannot authorize them and the events are dropped. FULL makes the whole
-- row available for the RLS check and the change payload. These tables are
-- low-volume, so the extra WAL cost is negligible.

-- Supabase ships the `supabase_realtime` publication, but guard for fresh DBs.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

do $$
declare
  t text;
  tables text[] := array[
    'products',
    'product_stock',
    'stock_movements',
    'ml_listings',
    'sales',
    'alerts',
    'product_categories'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I replica identity full', t);
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
