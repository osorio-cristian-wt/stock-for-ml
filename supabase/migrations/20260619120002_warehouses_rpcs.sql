-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 11 · Warehouses — client RPCs + realtime                           ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- The two-phase per-warehouse stock backend already exists (warehouses,
-- product_stock, buckets, apply_stock_movement with warehouse_id). This adds the
-- thin client-facing surface the Flutter app needs: ensure the default
-- ("Depósito principal", the dispatch warehouse), switch which one is default,
-- and transfer stock between warehouses for internal control.

-- ── Ensure the caller has a default warehouse, return its id ─────────
-- Wraps the SECURITY DEFINER ensure_default_warehouse(profile) so the app can
-- call it with no args (scoped to auth.uid()).
create or replace function public.ensure_default_warehouse_self()
returns uuid
language sql
security invoker
set search_path = public
as $$
  select public.ensure_default_warehouse((select auth.uid()));
$$;

-- ── Switch the default (dispatch) warehouse ─────────────────────────
-- ML sales/dispatch discount from the default warehouse. Only one default per
-- profile (warehouses_one_default_idx). Unset the old one first, then set the new
-- one, so the partial unique index never sees two defaults at once.
create or replace function public.set_default_warehouse(p_warehouse_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_profile uuid;
begin
  select profile_id into v_profile
    from public.warehouses where id = p_warehouse_id;
  if v_profile is null then
    raise exception 'warehouse % not found', p_warehouse_id;
  end if;

  update public.warehouses
     set is_default = false, updated_at = now()
   where profile_id = v_profile and is_default and id <> p_warehouse_id;

  update public.warehouses
     set is_default = true, updated_at = now()
   where id = p_warehouse_id;
end;
$$;

-- ── Transfer stock between two warehouses (internal control) ─────────
-- Two paired on_hand movements (out of A, into B) sharing a reference so they can
-- be recognised as a transfer. origin=user, but a balanced transfer between
-- sellable warehouses leaves the published `available` unchanged → the ML push is
-- a no-op. Moving to/from a non-sellable warehouse legitimately changes available.
create or replace function public.transfer_stock(
  p_product_id     uuid,
  p_from_warehouse uuid,
  p_to_warehouse   uuid,
  p_qty            int,
  p_note           text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_profile uuid;
  v_ref     text := gen_random_uuid()::text;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'transfer quantity must be positive';
  end if;
  if p_from_warehouse = p_to_warehouse then
    raise exception 'source and destination warehouses must differ';
  end if;

  select profile_id into v_profile from public.products where id = p_product_id;
  if v_profile is null then
    raise exception 'product % not found', p_product_id;
  end if;

  insert into public.stock_movements
    (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note, created_by)
  values
    (v_profile, p_product_id, p_from_warehouse, 'on_hand', -p_qty, 'transfer', 'user',
     v_ref, coalesce(p_note, 'Transferencia (salida)'), (select auth.uid())),
    (v_profile, p_product_id, p_to_warehouse, 'on_hand', p_qty, 'transfer', 'user',
     v_ref, coalesce(p_note, 'Transferencia (entrada)'), (select auth.uid()));
end;
$$;

-- ── Realtime: the app streams the warehouse list ────────────────────
do $$
begin
  execute 'alter table public.warehouses replica identity full';
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'warehouses'
  ) then
    alter publication supabase_realtime add table public.warehouses;
  end if;
end $$;
