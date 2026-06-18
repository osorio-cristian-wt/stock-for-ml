-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 04 · Views (economics & dashboards)                                ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- Per-listing economics: profit, markup (over cost) and margin (over price).
-- security_invoker = true => underlying table RLS applies to the caller.
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
    coalesce(public.latest_fx_rate(p.purchase_currency, l.currency_id, coalesce(st.fx_kind, 'blue')), 0) as fx_rate,
    round(p.purchase_cost
          * coalesce(public.latest_fx_rate(p.purchase_currency, l.currency_id, coalesce(st.fx_kind, 'blue')), 0), 2) as cost_in_sale_currency,
    coalesce(l.est_sale_fee, 0) as est_sale_fee,
    round(
      coalesce(l.price, 0)
      - coalesce(l.est_sale_fee, 0)
      - p.purchase_cost * coalesce(public.latest_fx_rate(p.purchase_currency, l.currency_id, coalesce(st.fx_kind, 'blue')), 0)
    , 2) as net_profit
  from public.ml_listings l
  join public.products    p  on p.id = l.product_id
  left join public.app_settings st on st.profile_id = l.profile_id
) base;

comment on view public.v_product_economics is
  'Profit/markup/margin per listing. Costs (USD) converted to sale currency via latest fx rate.';

-- Unread alerts count per profile (handy for badges).
create view public.v_unread_alert_counts
with (security_invoker = true) as
select profile_id, count(*) as unread
from public.alerts
where is_read = false
group by profile_id;
