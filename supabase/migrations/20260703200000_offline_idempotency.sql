-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 20 · Idempotencia para la cola offline (B1)                        ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- La app va a encolar operaciones en el dispositivo cuando no hay red
-- (docs/analisis-cola-offline.md, etapa B1) y reintentarlas al reconectar.
-- Para que un reintento duplicado sea no-op, cada RPC acepta un id definido
-- por el cliente:
--   · create_local_sale ya lo tiene (p_sale_id).
--   · close_purchase ya es idempotente por estado (draft → closed una vez).
--   · transfer_stock  → nuevo p_reference (antes generaba gen_random_uuid()
--     server-side en cada llamada: un reintento duplicaba la transferencia).
--   · apply_stock_movement → nuevo p_movement_id (antes insertaba siempre).

-- ── transfer_stock v2: reference provisto por el cliente ─────────────
-- Cambia la firma → se dropea la v1 para evitar ambigüedad de overload.
drop function if exists public.transfer_stock(uuid, uuid, uuid, int, text);

create or replace function public.transfer_stock(
  p_product_id     uuid,
  p_from_warehouse uuid,
  p_to_warehouse   uuid,
  p_qty            int,
  p_note           text default null,
  p_reference      text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_profile uuid;
  v_ref     text := coalesce(p_reference, gen_random_uuid()::text);
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'transfer quantity must be positive';
  end if;
  if p_from_warehouse = p_to_warehouse then
    raise exception 'source and destination warehouses must differ';
  end if;

  -- Idempotencia: si el cliente ya mandó esta transferencia (mismo
  -- reference), el reintento es no-op. Usa stock_movements_reference_idx.
  if p_reference is not null and exists (
    select 1 from public.stock_movements
     where reference = p_reference and reason = 'transfer'
  ) then
    return;
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

-- ── apply_stock_movement v3: id del movimiento provisto por el cliente ──
-- Cambia la firma → se dropea la v2 (8 args) para evitar ambigüedad.
drop function if exists public.apply_stock_movement(
  uuid, int, public.stock_reason, text, text, uuid, public.stock_bucket, public.stock_origin);

create or replace function public.apply_stock_movement(
  p_product_id   uuid,
  p_delta        int,
  p_reason       public.stock_reason,
  p_reference    text default null,
  p_note         text default null,
  p_warehouse_id uuid default null,
  p_bucket       public.stock_bucket default 'on_hand',
  p_origin       public.stock_origin default 'user',
  p_movement_id  uuid default null
)
returns uuid
language plpgsql
security invoker
as $$
declare
  v_profile uuid;
  v_id      uuid;
begin
  -- Idempotencia: reintento con el mismo id devuelve el movimiento existente.
  if p_movement_id is not null then
    select id into v_id from public.stock_movements where id = p_movement_id;
    if found then
      return v_id;
    end if;
  end if;

  select profile_id into v_profile from public.products where id = p_product_id;
  if v_profile is null then
    raise exception 'product % not found', p_product_id;
  end if;

  insert into public.stock_movements
    (id, profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note, created_by)
  values
    (coalesce(p_movement_id, gen_random_uuid()), v_profile, p_product_id, p_warehouse_id,
     p_bucket, p_delta, p_reason, p_origin, p_reference, p_note, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;
