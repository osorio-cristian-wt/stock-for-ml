-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 20 · RF-39 — Cargos tipados por venta (sale_charges)               ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Hoy solo se captura la comisión (order_items[].sale_fee); el costo de envío
-- del vendedor y los impuestos de la orden no se registran y la ganancia por
-- venta queda inflada. Cada cargo pasa a ser una fila tipada: agregar un tipo
-- de cargo nuevo (descuentos, financiación, …) no toca el schema.
--
-- Población: reconcileOrder (Edge) borra+inserta los cargos de la venta en la
-- misma pasada idempotente que sale_items. Fuentes ML: order_items.sale_fee
-- (comisión, POR UNIDAD según docs ML), GET /shipments/{id}/costs →
-- senders[].cost (envío a cargo del vendedor) y order.taxes (impuestos).

create type public.sale_charge_kind as enum (
  'commission', 'shipping', 'tax', 'discount', 'financing', 'other'
);

create table public.sale_charges (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  sale_id     uuid not null references public.sales(id) on delete cascade,
  kind        public.sale_charge_kind not null,
  -- Monto que SOPORTA el vendedor (positivo = le cuesta plata).
  amount      numeric(14,2) not null default 0,
  currency_id text not null default 'ARS',
  -- De qué recurso de ML salió el dato (order | shipment | payment | billing).
  source      text,
  raw         jsonb,
  created_at  timestamptz not null default now()
);
create index sale_charges_sale_idx on public.sale_charges (sale_id);
create index sale_charges_profile_idx on public.sale_charges (profile_id);

comment on table public.sale_charges is
  'RF-39: cargos de una venta (comisión, envío del vendedor, impuestos, …). Fila por cargo; idempotente vía delete+insert por venta.';

alter table public.sale_charges enable row level security;
create policy "sale_charges owner" on public.sale_charges
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ── v_sale_profit v3: descuenta TODOS los cargos ─────────────────────
-- Con cargos registrados: net = bruto − Σ sale_charges − COGS.
-- Sin cargos (ventas locales o ML previas a RF-39): cae a las columnas
-- legacy sale_fee + shipping_cost, como hasta ahora.
-- (drop + create: la columna nueva charges_ars va en el medio y
--  `create or replace view` no permite reordenar columnas.)
drop view public.v_sale_profit;
create view public.v_sale_profit
with (security_invoker = true) as
select
  s.id  as sale_id,
  s.profile_id,
  s.sold_at,
  s.status,
  s.channel,
  coalesce(s.total_amount, s.quantity * s.unit_price) as gross,
  s.sale_fee,
  s.shipping_cost,
  coalesce(ch.total, s.sale_fee + s.shipping_cost) as charges_ars,
  round(coalesce(items.cost_ars,
                 s.quantity * public.product_cost_ars(s.product_id)), 2) as cost_ars,
  round(
    coalesce(s.total_amount, s.quantity * s.unit_price)
    - coalesce(ch.total, s.sale_fee + s.shipping_cost)
    - coalesce(items.cost_ars,
               s.quantity * public.product_cost_ars(s.product_id), 0)
  , 2) as net_profit
from public.sales s
left join lateral (
  select sum(si.quantity * coalesce(public.product_cost_ars(si.product_id), 0)) as cost_ars
    from public.sale_items si
   where si.sale_id = s.id
  having count(*) > 0
) items on true
left join lateral (
  select sum(sc.amount) as total
    from public.sale_charges sc
   where sc.sale_id = s.id
  having count(*) > 0
) ch on true;

comment on view public.v_sale_profit is
  'Ganancia por venta: bruto − cargos (sale_charges; fallback comisión+envío legacy) − COGS por política.';
