-- pgTAP tests: schema, RLS posture, triggers and the economics view.
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(20);

-- ── Schema presence ─────────────────────────────────────────────────
select has_table('public', 'products',            'products table exists');
select has_table('public', 'ml_listings',         'ml_listings table exists');
select has_table('public', 'ml_credentials',      'ml_credentials table exists');
select has_table('public', 'stock_movements',     'stock_movements table exists');
select has_table('public', 'sales',               'sales table exists');
select has_table('public', 'fx_rates',            'fx_rates table exists');
select has_view ('public', 'v_product_economics', 'economics view exists');

-- ── RLS posture ─────────────────────────────────────────────────────
select ok((select relrowsecurity from pg_class where oid = 'public.products'::regclass),
          'RLS enabled on products');
select ok((select relrowsecurity from pg_class where oid = 'public.ml_credentials'::regclass),
          'RLS enabled on ml_credentials');

-- Sensitive tables must have ZERO policies => clients are denied entirely.
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='ml_credentials'),
          0, 'ml_credentials has no client policies (deny-all)');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='ml_events'),
          0, 'ml_events has no client policies (deny-all)');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='oauth_states'),
          0, 'oauth_states has no client policies (deny-all)');

-- ── Functional: user bootstrap + triggers + economics ───────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111111',
  'authenticated', 'authenticated', 'tester@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

select is((select count(*)::int from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
          1, 'profile auto-created by handle_new_user trigger');
select is((select count(*)::int from public.app_settings where profile_id = '11111111-1111-1111-1111-111111111111'),
          1, 'app_settings auto-created by handle_new_user trigger');

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Test Product', 10, 'USD');

insert into public.fx_rates (base_currency, quote_currency, kind, rate)
values ('USD', 'ARS', 'blue', 1000);

insert into public.stock_movements (profile_id, product_id, delta, reason)
values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 5, 'purchase');

select is((select current_stock from public.products where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
          5, 'stock_movements trigger updates current_stock');

insert into public.ml_listings (profile_id, product_id, ml_item_id, price, currency_id, est_sale_fee, available_quantity)
values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'MLAX', 20000, 'ARS', 2000, 5);

-- cost = 10 * 1000 = 10000 ; net = 20000 - 2000 - 10000 = 8000
-- markup = 8000/10000 = 80% ; margin = 8000/20000 = 40%
select is((select net_profit from public.v_product_economics where ml_item_id = 'MLAX'),
          8000.00::numeric, 'economics: net_profit');
select is((select markup_pct from public.v_product_economics where ml_item_id = 'MLAX'),
          80.00::numeric, 'economics: markup_pct');
select is((select margin_pct from public.v_product_economics where ml_item_id = 'MLAX'),
          40.00::numeric, 'economics: margin_pct');

-- Sell everything -> stock 0 -> out_of_stock alert fires.
-- (El trigger v2 también alertó al CREAR el producto en 0; esa alerta se
-- silenció sola al reponer, por eso acá se cuentan solo las NO leídas.)
insert into public.stock_movements (profile_id, product_id, delta, reason, reference)
values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', -5, 'sale', 'ORDER-1');

select is((select current_stock from public.products where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
          0, 'stock decremented to 0');
select is((select count(*)::int from public.alerts
           where product_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
             and type = 'out_of_stock' and is_read = false),
          1, 'out_of_stock alert created by trigger');

select * from finish();
rollback;
