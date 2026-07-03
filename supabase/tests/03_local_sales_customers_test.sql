-- pgTAP: ventas locales (create_local_sale, canal ml/local) y padrón de
-- clientes/proveedores con datos extra.
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(18);

-- ── Fixtures: user + producto con stock ─────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '44444444-4444-4444-4444-444444444444',
  'authenticated', 'authenticated', 'local-sales@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency)
values ('abababab-abab-abab-abab-abababababab',
        '44444444-4444-4444-4444-444444444444', 'Local Sale Product', 5, 'USD');

select public.ensure_default_warehouse('44444444-4444-4444-4444-444444444444');
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('44444444-4444-4444-4444-444444444444',
        'abababab-abab-abab-abab-abababababab', 10, 'purchase', 'on_hand', 'user');

select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          10, 'semilla: 10 disponibles');

-- ── Clientes ────────────────────────────────────────────────────────
select lives_ok(
  $$insert into public.customers (profile_id, name)
    values ('44444444-4444-4444-4444-444444444444', 'Juan Pérez')$$,
  'customers: alta solo con nombre');
select throws_ok(
  $$insert into public.customers (profile_id, name)
    values ('44444444-4444-4444-4444-444444444444', 'juan pérez')$$,
  '23505', null, 'customers: nombre duplicado (case-insensitive) rechazado');

-- ── Proveedores con datos extra ─────────────────────────────────────
select lives_ok(
  $$insert into public.suppliers (profile_id, name, legal_name, tax_id)
    values ('44444444-4444-4444-4444-444444444444',
            'Mayorista Sur', 'Mayorista Sur S.R.L.', '30-71234567-8')$$,
  'suppliers: alta con razón social y CUIT');
select is((select tax_id from public.suppliers where name = 'Mayorista Sur'),
          '30-71234567-8', 'suppliers: el CUIT persiste');

-- ── Venta local con cliente ─────────────────────────────────────────
select ok(
  public.create_local_sale(
    'abababab-abab-abab-abab-abababababab', 3, 100.00,
    (select id from public.customers where name = 'Juan Pérez'),
    null, 'venta mostrador') is not null,
  'create_local_sale: crea y devuelve id');

select is((select count(*)::int from public.sales
           where product_id = 'abababab-abab-abab-abab-abababababab'
             and channel = 'local'),
          1, 'venta local: una fila con channel=local');
select is((select quantity from public.sales where channel = 'local'
             and product_id = 'abababab-abab-abab-abab-abababababab'),
          3, 'venta local: cantidad 3');
select is((select net_amount from public.sales where channel = 'local'
             and product_id = 'abababab-abab-abab-abab-abababababab'),
          300.00::numeric(14,2), 'venta local: neto = qty × precio (sin comisión)');
select is((select customer_id from public.sales where channel = 'local'
             and product_id = 'abababab-abab-abab-abab-abababababab'),
          (select id from public.customers where name = 'Juan Pérez'),
          'venta local: cliente asignado');
select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          7, 'venta local: descuenta stock (10 − 3)');
select is((select count(*)::int from public.stock_movements m
            join public.sales s on s.id::text = m.reference
           where m.reason = 'sale' and m.origin = 'user'
             and s.channel = 'local'),
          1, 'venta local: movimiento sale/user con reference = venta');
select ok(
  exists(select 1 from public.stock_push_queue
          where product_id = 'abababab-abab-abab-abab-abababababab'),
  'venta local: encola push del nuevo disponible a ML');

-- ── Venta local sin cliente ─────────────────────────────────────────
select ok(
  public.create_local_sale(
    'abababab-abab-abab-abab-abababababab', 1, 50.00) is not null,
  'create_local_sale: funciona sin cliente');
select is((select customer_id from public.sales where channel = 'local'
             and quantity = 1),
          null::uuid, 'venta local: customer_id queda null');
select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          6, 'venta local: segundo descuento (7 − 1)');

-- ── Validaciones ────────────────────────────────────────────────────
select throws_ok(
  $$select public.create_local_sale(
      'abababab-abab-abab-abab-abababababab', 0, 10.00)$$,
  'P0001', null, 'create_local_sale: cantidad <= 0 lanza excepción');
select throws_ok(
  $$insert into public.sales (profile_id, channel, quantity, unit_price)
    values ('44444444-4444-4444-4444-444444444444', 'ml', 1, 10)$$,
  '23514', null, 'sales: canal ml sin ml_order_id viola el check');

select * from finish();
rollback;
