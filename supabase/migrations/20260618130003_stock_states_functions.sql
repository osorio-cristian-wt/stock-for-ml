-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 09 · Stock states — functions & triggers                           ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- updated_at maintenance for the new owner-scoped tables.
create trigger trg_warehouses_updated
  before update on public.warehouses
  for each row execute function public.tg_set_updated_at();
create trigger trg_product_categories_updated
  before update on public.product_categories
  for each row execute function public.tg_set_updated_at();

-- ── Default warehouse (lazily created per profile) ──────────────────
create or replace function public.ensure_default_warehouse(p_profile uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.warehouses
   where profile_id = p_profile and is_default
   limit 1;
  if v_id is null then
    insert into public.warehouses (profile_id, code, name, is_default, is_sellable)
    values (p_profile, 'PRINCIPAL', 'Depósito principal', true, true)
    on conflict (profile_id, code) do update set is_default = true
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- ── BEFORE insert: resolve the warehouse for a movement ─────────────
create or replace function public.tg_resolve_movement_warehouse()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.warehouse_id is null then
    new.warehouse_id := public.ensure_default_warehouse(new.profile_id);
  end if;
  return new;
end;
$$;

create trigger trg_resolve_movement_warehouse
  before insert on public.stock_movements
  for each row execute function public.tg_resolve_movement_warehouse();

-- ── AFTER insert: maintain product_stock buckets + products.current_stock ──
-- current_stock is the AVAILABLE total = Σ (on_hand − reserved) over sellable
-- warehouses (the number published to ML). Non-ML movements enqueue an ML push.
create or replace function public.tg_apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.product_stock (profile_id, product_id, warehouse_id, incoming, on_hand, reserved)
  values (
    new.profile_id, new.product_id, new.warehouse_id,
    case when new.bucket = 'incoming' then new.delta else 0 end,
    case when new.bucket = 'on_hand'  then new.delta else 0 end,
    case when new.bucket = 'reserved' then new.delta else 0 end
  )
  on conflict (product_id, warehouse_id) do update set
    incoming = product_stock.incoming + excluded.incoming,
    on_hand  = product_stock.on_hand  + excluded.on_hand,
    reserved = product_stock.reserved + excluded.reserved,
    updated_at = now();

  update public.products p set
    current_stock = coalesce((
      select sum(ps.on_hand - ps.reserved)
        from public.product_stock ps
        join public.warehouses w on w.id = ps.warehouse_id
       where ps.product_id = new.product_id and w.is_sellable
    ), 0),
    updated_at = now()
  where p.id = new.product_id;

  -- Anti-loop: only user/system-origin changes are pushed back to ML.
  if new.origin <> 'ml' then
    insert into public.stock_push_queue (product_id)
    values (new.product_id)
    on conflict (product_id) do update set
      status = 'pending', enqueued_at = now(), processed_at = null, error = null;
  end if;

  return new;
end;
$$;

-- ── apply_stock_movement v2 (RPC for app/Edge) ──────────────────────
-- Drops the v1 (5-arg) signature to avoid overload ambiguity.
drop function if exists public.apply_stock_movement(uuid, int, public.stock_reason, text, text);

create or replace function public.apply_stock_movement(
  p_product_id   uuid,
  p_delta        int,
  p_reason       public.stock_reason,
  p_reference    text default null,
  p_note         text default null,
  p_warehouse_id uuid default null,
  p_bucket       public.stock_bucket default 'on_hand',
  p_origin       public.stock_origin default 'user'
)
returns uuid
language plpgsql
security invoker
as $$
declare
  v_profile uuid;
  v_id      uuid;
begin
  select profile_id into v_profile from public.products where id = p_product_id;
  if v_profile is null then
    raise exception 'product % not found', p_product_id;
  end if;

  insert into public.stock_movements
    (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note, created_by)
  values
    (v_profile, p_product_id, p_warehouse_id, p_bucket, p_delta, p_reason, p_origin,
     p_reference, p_note, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

-- ── Idempotent order reconciliation (called by Edge Functions) ──────
-- p_targets: jsonb array of { product_id, reserved, on_hand } = the cumulative
-- effect the order must have, given its current ML status. We compute the diff
-- against the movements already applied for this order and insert compensators.
create or replace function public.reconcile_order_stock(
  p_profile_id   uuid,
  p_order_id     text,
  p_warehouse_id uuid,
  p_targets      jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wh      uuid := coalesce(p_warehouse_id, public.ensure_default_warehouse(p_profile_id));
  t         jsonb;
  v_pid     uuid;
  v_bucket  public.stock_bucket;
  v_desired int;
  v_current int;
  v_delta   int;
begin
  -- One worker per order: serialize concurrent process-events / sync-orders.
  perform pg_advisory_xact_lock(hashtextextended(p_order_id, 0));

  for t in select * from jsonb_array_elements(p_targets) loop
    v_pid := (t->>'product_id')::uuid;
    foreach v_bucket in array array['reserved', 'on_hand']::public.stock_bucket[] loop
      v_desired := coalesce((t->>(v_bucket::text))::int, 0);
      select coalesce(sum(delta), 0) into v_current
        from public.stock_movements
       where reference = p_order_id and product_id = v_pid and bucket = v_bucket;
      v_delta := v_desired - v_current;
      if v_delta <> 0 then
        insert into public.stock_movements
          (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
        values (
          p_profile_id, v_pid, v_wh, v_bucket, v_delta,
          case
            when v_bucket = 'reserved' and v_delta > 0 then 'reserve'
            when v_bucket = 'reserved' and v_delta < 0 then 'cancellation'
            when v_bucket = 'on_hand'  and v_delta < 0 then 'dispatch'
            else 'return'
          end::public.stock_reason,
          'ml', p_order_id, 'reconcile ' || p_order_id
        );
      end if;
    end loop;
  end loop;
end;
$$;
