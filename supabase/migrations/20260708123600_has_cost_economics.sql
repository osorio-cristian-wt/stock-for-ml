-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 21 · RF-40 — Sin costo cargado ⇒ sin ganancia calculada             ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Antes: coalesce(costo, 0) hacía que un producto SIN costo mostrara
-- ganancia = precio − comisión (inflada) en stats y Comparativa. Ahora las
-- vistas exponen has_cost / has_full_cost y devuelven net_profit/markup/
-- margen NULL cuando falta el costo: la app los muestra como "a completar"
-- y los excluye de los agregados.

-- ── v_product_economics v3: has_cost + profit null sin costo ─────────
drop view public.v_product_economics;
create view public.v_product_economics
with (security_invoker = true) as
select
  base.*,
  case when base.has_cost and base.cost_in_sale_currency > 0
       then round(base.net_profit / base.cost_in_sale_currency * 100, 2)
  end as markup_pct,
  case when base.has_cost and base.sale_price > 0
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
    -- RF-37: estado de la publicación para chips/filtros sin otra query.
    l.status                   as listing_status,
    l.sub_status,
    l.logistic_type,
    -- RF-42: link a la publicación ("el precio se cambia en ML").
    l.permalink,
    coalesce(public.product_cost_ars(p.id), 0) > 0 as has_cost,
    case when coalesce(public.product_cost_ars(p.id), 0) > 0 then
      round(
        coalesce(l.price, 0)
        - coalesce(l.est_sale_fee, 0)
        - coalesce(public.product_cost_ars(p.id), 0)
      , 2)
    end as net_profit
  from public.ml_listings l
  join public.products    p  on p.id = l.product_id
  left join public.app_settings st on st.profile_id = l.profile_id
) base;

comment on view public.v_product_economics is
  'Profit/markup/margin per listing (costo por política, ARS). has_cost=false ⇒ net_profit/markup/margin NULL (RF-40).';

-- ── v_sale_profit v4: has_full_cost + profit null sin costo ──────────
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
  case when coalesce(items.has_cost, single.has_cost, false) then
    round(coalesce(items.cost_ars, s.quantity * single.cost_ars), 2)
  end as cost_ars,
  coalesce(items.has_cost, single.has_cost, false) as has_full_cost,
  case when coalesce(items.has_cost, single.has_cost, false) then
    round(
      coalesce(s.total_amount, s.quantity * s.unit_price)
      - coalesce(ch.total, s.sale_fee + s.shipping_cost)
      - coalesce(items.cost_ars, s.quantity * single.cost_ars)
    , 2)
  end as net_profit
from public.sales s
left join lateral (
  -- Ventas multi-línea: el COGS solo vale si TODAS las líneas tienen costo.
  select sum(si.quantity * coalesce(public.product_cost_ars(si.product_id), 0)) as cost_ars,
         bool_and(coalesce(public.product_cost_ars(si.product_id), 0) > 0)      as has_cost
    from public.sale_items si
   where si.sale_id = s.id
  having count(*) > 0
) items on true
left join lateral (
  select public.product_cost_ars(s.product_id) as cost_ars,
         coalesce(public.product_cost_ars(s.product_id), 0) > 0 as has_cost
   where s.product_id is not null
) single on true
left join lateral (
  select sum(sc.amount) as total
    from public.sale_charges sc
   where sc.sale_id = s.id
  having count(*) > 0
) ch on true;

comment on view public.v_sale_profit is
  'Ganancia por venta: bruto − cargos − COGS. has_full_cost=false ⇒ cost_ars/net_profit NULL (RF-40).';
