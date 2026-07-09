-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 23 · RF-38 — Depósito "Full (ML)": espejo read-only + atribución    ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Modelo (aprobado 2026-07-08):
--   · Un depósito especial por perfil (ml_fulfillment=true, NO vendible) espeja
--     el stock que ML administra en sus centros Full. La verdad de ese stock la
--     fija ML: la app nunca lo empuja (push-stock además saltea publicaciones
--     con logistic_type=fulfillment).
--   · Órdenes con envío fulfillment reconcilian contra este depósito (antes
--     descontaban del depósito de despacho local y corrompían el disponible).
--   · Si el espejo DETECTA MÁS stock en Full (mercadería recibida), el delta
--     queda en full_inbounds como "sin atribuir": el usuario elige de qué
--     depósito local salió → descuento SOLO local (origin=ml ⇒ sin push), o
--     lo descarta (p. ej. compra que entró directo a Full).

-- ── Columnas nuevas ──────────────────────────────────────────────────
alter table public.warehouses
  add column ml_fulfillment boolean not null default false;
comment on column public.warehouses.ml_fulfillment is
  'Depósito espejo del stock en centros Full de ML (read-only, no vendible, sin push).';

-- Un solo depósito Full por perfil.
create unique index warehouses_one_full_idx
  on public.warehouses (profile_id) where ml_fulfillment;

alter table public.ml_listings
  add column logistic_type text,
  add column inventory_id  text;
comment on column public.ml_listings.logistic_type is
  'shipping.logistic_type del ítem ML (fulfillment ⇒ stock administrado por ML).';

-- ── Ingresos a Full sin atribuir ─────────────────────────────────────
create table public.full_inbounds (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  product_id   uuid not null references public.products(id) on delete cascade,
  ml_item_id   text,
  qty          int  not null check (qty > 0),
  status       text not null default 'pending'
               check (status in ('pending', 'attributed', 'dismissed')),
  -- Depósito local del que salió la mercadería (al atribuir).
  warehouse_id uuid references public.warehouses(id) on delete set null,
  detected_at  timestamptz not null default now(),
  resolved_at  timestamptz,
  note         text
);
create index full_inbounds_pending_idx
  on public.full_inbounds (profile_id, status, detected_at desc);
comment on table public.full_inbounds is
  'RF-38: aumentos de stock detectados en Full pendientes de atribuir a un depósito local.';

alter table public.full_inbounds enable row level security;
create policy "full_inbounds owner" on public.full_inbounds
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ── Depósito Full (lazy, por perfil) ─────────────────────────────────
create or replace function public.ensure_full_warehouse(p_profile uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.warehouses
   where profile_id = p_profile and ml_fulfillment
   limit 1;
  if v_id is null then
    insert into public.warehouses (profile_id, code, name, is_default, is_sellable, ml_fulfillment)
    values (p_profile, 'ML_FULL', 'Full (ML)', false, false, true)
    on conflict (profile_id, code) do update set ml_fulfillment = true, is_sellable = false
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- ── Espejo idempotente del stock Full de un producto ─────────────────
-- p_qty = stock que ML reporta en Full. Inserta el movimiento compensador
-- (origin=ml ⇒ no push) y, si el stock SUBIÓ, deja el delta en full_inbounds
-- para que el usuario lo atribuya. Devuelve el delta aplicado.
-- p_track_inbound=false en la siembra inicial (producto recién creado por el
-- import: no hay stock local del que pueda haber salido).
create or replace function public.reconcile_full_stock(
  p_profile_id    uuid,
  p_product_id    uuid,
  p_qty           int,
  p_reference     text default null,
  p_track_inbound boolean default true
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wh      uuid := public.ensure_full_warehouse(p_profile_id);
  v_current int;
  v_delta   int;
begin
  perform pg_advisory_xact_lock(hashtextextended('full:' || p_product_id::text, 0));

  select coalesce(on_hand, 0) into v_current
    from public.product_stock
   where product_id = p_product_id and warehouse_id = v_wh;
  v_delta := coalesce(p_qty, 0) - coalesce(v_current, 0);
  if v_delta = 0 then
    return 0;
  end if;

  insert into public.stock_movements
    (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
  values
    (p_profile_id, p_product_id, v_wh, 'on_hand', v_delta,
     'full_sync', 'ml', p_reference, 'Espejo de stock Full (ML)');

  if v_delta > 0 and p_track_inbound then
    insert into public.full_inbounds (profile_id, product_id, ml_item_id, qty)
    values (p_profile_id, p_product_id, p_reference, v_delta);
  end if;

  return v_delta;
end;
$$;

-- ── Atribuir / descartar un ingreso a Full (lo llama la app) ─────────
-- Atribuir: la mercadería salió de un depósito local ⇒ descuento local con
-- origin=ml para NO empujar a ML (ML ya la contabilizó al recibirla en Full).
create or replace function public.attribute_full_inbound(
  p_inbound_id   uuid,
  p_warehouse_id uuid
)
returns void
language plpgsql
security invoker
as $$
declare
  v_row public.full_inbounds%rowtype;
begin
  select * into v_row from public.full_inbounds
   where id = p_inbound_id and status = 'pending'
   for update;
  if v_row.id is null then
    raise exception 'ingreso a Full % inexistente o ya resuelto', p_inbound_id;
  end if;
  if not exists (
    select 1 from public.warehouses w
     where w.id = p_warehouse_id
       and w.profile_id = v_row.profile_id
       and not w.ml_fulfillment
  ) then
    raise exception 'depósito % inválido para atribuir', p_warehouse_id;
  end if;

  insert into public.stock_movements
    (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note, created_by)
  values
    (v_row.profile_id, v_row.product_id, p_warehouse_id, 'on_hand', -v_row.qty,
     'full_inbound', 'ml', v_row.id::text,
     'Salida a Full (ML) atribuida por el usuario', auth.uid());

  update public.full_inbounds
     set status = 'attributed', warehouse_id = p_warehouse_id, resolved_at = now()
   where id = p_inbound_id;
end;
$$;

create or replace function public.dismiss_full_inbound(p_inbound_id uuid)
returns void
language plpgsql
security invoker
as $$
begin
  update public.full_inbounds
     set status = 'dismissed', resolved_at = now()
   where id = p_inbound_id and status = 'pending';
  if not found then
    raise exception 'ingreso a Full % inexistente o ya resuelto', p_inbound_id;
  end if;
end;
$$;
