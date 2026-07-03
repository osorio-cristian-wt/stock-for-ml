-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 19 · Costeo por política (FIFO / promedio / último / manual)        ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Pedido del dueño: la ganancia neta debe salir del costo de COMPRA real
-- (según la política elegida, ej. FIFO) comparado con el precio de venta —
-- no del costo manual del producto. La política se elige en Ajustes.
--
-- v1 documentada: el costo vigente por política se calcula al día de hoy
-- (capas de compras CERRADAS convertidas a ARS al tipo de cambio actual).
-- El COGS de una venta usa el costo vigente, no el histórico al momento de
-- la venta; si más adelante hace falta el histórico exacto, se materializa
-- el costo en sale_items al confirmar la venta.

create type public.cost_policy as enum ('fifo', 'avg', 'last', 'manual');

alter table public.app_settings
  add column cost_policy public.cost_policy not null default 'fifo';
comment on column public.app_settings.cost_policy is
  'Cómo valuar el costo de lo vendido: fifo (capa más vieja en stock), avg (promedio ponderado), last (última compra), manual (costo cargado en el producto).';

-- ── Factor de conversión a ARS (ARS→ARS = 1; sin cotización = 0) ─────
create or replace function public.to_ars_rate(p_currency text, p_kind public.fx_kind)
returns numeric
language sql
stable
as $$
  select case
    when p_currency = 'ARS' then 1
    else coalesce(public.latest_fx_rate(p_currency, 'ARS', p_kind), 0)
  end;
$$;

-- ── Costo unitario vigente (ARS) según la política del perfil ────────
create or replace function public.product_cost_ars(
  p_product_id uuid,
  p_policy     public.cost_policy default null
)
returns numeric
language plpgsql
stable
as $$
declare
  v_profile  uuid;
  v_manual   numeric;
  v_currency text;
  v_policy   public.cost_policy;
  v_kind     public.fx_kind;
  v_cost     numeric;
  v_onhand   numeric;
  v_bought   numeric;
  v_consumed numeric;
  v_cum      numeric := 0;
  r          record;
begin
  select profile_id, purchase_cost, purchase_currency
    into v_profile, v_manual, v_currency
    from public.products where id = p_product_id;
  if v_profile is null then
    return null;
  end if;

  select coalesce(p_policy, st.cost_policy, 'fifo'),
         coalesce(st.fx_kind, 'blue')
    into v_policy, v_kind
    from (select 1) one
    left join public.app_settings st on st.profile_id = v_profile;

  if v_policy = 'last' then
    select pi.unit_cost * public.to_ars_rate(pu.currency, v_kind)
      into v_cost
      from public.purchase_items pi
      join public.purchases pu on pu.id = pi.purchase_id
     where pi.product_id = p_product_id and pu.status = 'closed'
     order by coalesce(pu.purchased_at, pu.created_at) desc, pi.created_at desc
     limit 1;

  elsif v_policy = 'avg' then
    select sum(pi.quantity * pi.unit_cost * public.to_ars_rate(pu.currency, v_kind))
           / nullif(sum(pi.quantity), 0)
      into v_cost
      from public.purchase_items pi
      join public.purchases pu on pu.id = pi.purchase_id
     where pi.product_id = p_product_id and pu.status = 'closed';

  elsif v_policy = 'fifo' then
    -- Capas de compra en orden cronológico; lo consumido = comprado − lo que
    -- queda físico (on_hand en todos los depósitos). La capa donde "empieza"
    -- el stock remanente da el costo vigente.
    select coalesce(sum(on_hand), 0) into v_onhand
      from public.product_stock where product_id = p_product_id;
    select coalesce(sum(pi.quantity), 0) into v_bought
      from public.purchase_items pi
      join public.purchases pu on pu.id = pi.purchase_id
     where pi.product_id = p_product_id and pu.status = 'closed';
    v_consumed := greatest(v_bought - v_onhand, 0);

    for r in
      select pi.quantity,
             pi.unit_cost * public.to_ars_rate(pu.currency, v_kind) as cost_ars
        from public.purchase_items pi
        join public.purchases pu on pu.id = pi.purchase_id
       where pi.product_id = p_product_id and pu.status = 'closed'
       order by coalesce(pu.purchased_at, pu.created_at), pi.created_at
    loop
      v_cum := v_cum + r.quantity;
      v_cost := r.cost_ars;              -- si todo se consumió, queda la última
      if v_cum > v_consumed then
        exit;                            -- capa vigente encontrada
      end if;
    end loop;
  end if;
  -- 'manual' (o sin compras cerradas) cae al costo cargado en el producto.

  if v_cost is null then
    v_cost := v_manual * public.to_ars_rate(v_currency, v_kind);
  end if;
  return round(v_cost, 2);
end;
$$;

-- ── v_product_economics v2: costo por política ──────────────────────
-- Mantiene las columnas que consume la app; cost_in_sale_currency y
-- net_profit ahora salen de product_cost_ars (además arregla el caso de
-- costo manual en ARS, que antes multiplicaba por una cotización inexistente
-- y daba 0).
drop view public.v_product_economics;
create view public.v_product_economics
with (security_invoker = true) as
select
  base.*,
  case when base.cost_in_sale_currency > 0
       then round(base.net_profit / base.cost_in_sale_currency * 100, 2)
  end as markup_pct,
  case when base.sale_price > 0
       then round(base.net_profit / base.sale_price * 100, 2)
  end as margin_pct
from (
  select
    l.id                       as listing_id,
    l.profile_id,
    p.id                       as product_id,
    coalesce(p.title, l.title) as title,
    l.ml_item_id,
    l.price                    as sale_price,
    l.currency_id,
    p.purchase_cost,
    p.purchase_currency,
    coalesce(st.fx_kind, 'blue'::public.fx_kind) as fx_kind,
    public.to_ars_rate(p.purchase_currency, coalesce(st.fx_kind, 'blue')) as fx_rate,
    coalesce(public.product_cost_ars(p.id), 0) as cost_in_sale_currency,
    coalesce(l.est_sale_fee, 0) as est_sale_fee,
    round(
      coalesce(l.price, 0)
      - coalesce(l.est_sale_fee, 0)
      - coalesce(public.product_cost_ars(p.id), 0)
    , 2) as net_profit
  from public.ml_listings l
  join public.products    p  on p.id = l.product_id
  left join public.app_settings st on st.profile_id = l.profile_id
) base;

comment on view public.v_product_economics is
  'Profit/markup/margin per listing. Cost basis follows app_settings.cost_policy (FIFO por defecto), en ARS.';

-- ── Ganancia real por venta (ingreso − comisiones − costo por política) ─
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
  round(coalesce(items.cost_ars,
                 s.quantity * public.product_cost_ars(s.product_id)), 2) as cost_ars,
  round(
    coalesce(s.total_amount, s.quantity * s.unit_price)
    - s.sale_fee - s.shipping_cost
    - coalesce(items.cost_ars,
               s.quantity * public.product_cost_ars(s.product_id), 0)
  , 2) as net_profit
from public.sales s
left join lateral (
  select sum(si.quantity * coalesce(public.product_cost_ars(si.product_id), 0)) as cost_ars
    from public.sale_items si
   where si.sale_id = s.id
  having count(*) > 0
) items on true;

comment on view public.v_sale_profit is
  'Ganancia por venta: bruto − comisión − envío − COGS (costo por política de app_settings).';
