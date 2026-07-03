-- pgTAP: ventas locales multi-ítem (create_local_sale v2: transaccional +
-- idempotente + validación de stock por depósito), sale_items y padrón de
-- clientes/proveedores con datos extra.
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(36);

-- ── Fixtures: user + productos con stock ────────────────────────────
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

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency) values
  ('abababab-abab-abab-abab-abababababab',
   '44444444-4444-4444-4444-444444444444', 'Producto A', 5, 'USD'),
  ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd',
   '44444444-4444-4444-4444-444444444444', 'Producto B', 3, 'USD');

select public.ensure_default_warehouse('44444444-4444-4444-4444-444444444444');
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin) values
  ('44444444-4444-4444-4444-444444444444',
   'abababab-abab-abab-abab-abababababab', 10, 'purchase', 'on_hand', 'user'),
  ('44444444-4444-4444-4444-444444444444',
   'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd', 5, 'purchase', 'on_hand', 'user');

select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          10, 'semilla: producto A con 10 disponibles');

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

-- ── Venta local (1 ítem, con cliente) ───────────────────────────────
select is(
  public.create_local_sale(
    '[{"product_id":"abababab-abab-abab-abab-abababababab","quantity":3,"unit_price":100}]'::jsonb,
    (select id from public.customers where name = 'Juan Pérez'),
    null, 'venta mostrador',
    'a1a1a1a1-1111-1111-1111-111111111111'),
  'a1a1a1a1-1111-1111-1111-111111111111'::uuid,
  'venta 1 ítem: crea y devuelve el id pedido');

select is((select count(*)::int from public.sales where channel = 'local'),
          1, 'venta 1 ítem: una fila con channel=local');
select is((select quantity from public.sales
           where id = 'a1a1a1a1-1111-1111-1111-111111111111'),
          3, 'venta 1 ítem: cantidad 3');
select is((select net_amount from public.sales
           where id = 'a1a1a1a1-1111-1111-1111-111111111111'),
          300.00::numeric(14,2), 'venta 1 ítem: neto = qty × precio');
select is((select total_amount from public.sales
           where id = 'a1a1a1a1-1111-1111-1111-111111111111'),
          300.00::numeric(14,2), 'venta 1 ítem: total_amount = Σ líneas');
select is((select quantity from public.sale_items
           where sale_id = 'a1a1a1a1-1111-1111-1111-111111111111'),
          3, 'venta 1 ítem: una línea en sale_items con la cantidad');
select is((select customer_id from public.sales
           where id = 'a1a1a1a1-1111-1111-1111-111111111111'),
          (select id from public.customers where name = 'Juan Pérez'),
          'venta 1 ítem: cliente asignado');
select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          7, 'venta 1 ítem: descuenta stock (10 − 3)');
select is((select count(*)::int from public.stock_movements
           where reason = 'sale' and origin = 'user'
             and reference = 'a1a1a1a1-1111-1111-1111-111111111111'),
          1, 'venta 1 ítem: movimiento sale/user con reference = venta');
select ok(
  exists(select 1 from public.stock_push_queue
          where product_id = 'abababab-abab-abab-abab-abababababab'),
  'venta 1 ítem: encola push del nuevo disponible a ML');

-- ── Venta local multi-ítem ──────────────────────────────────────────
select is((select current_stock from public.products
           where id = 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd'),
          5, 'semilla: producto B con 5 disponibles');

select is(
  public.create_local_sale(
    '[{"product_id":"abababab-abab-abab-abab-abababababab","quantity":2,"unit_price":100},
      {"product_id":"cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd","quantity":1,"unit_price":50}]'::jsonb,
    null, null, null,
    'a2a2a2a2-2222-2222-2222-222222222222'),
  'a2a2a2a2-2222-2222-2222-222222222222'::uuid,
  'multi-ítem: crea la venta');

select is((select count(*)::int from public.sale_items
           where sale_id = 'a2a2a2a2-2222-2222-2222-222222222222'),
          2, 'multi-ítem: una línea por producto');
select is((select total_amount from public.sales
           where id = 'a2a2a2a2-2222-2222-2222-222222222222'),
          250.00::numeric(14,2), 'multi-ítem: total 2×100 + 1×50');
select is((select quantity from public.sales
           where id = 'a2a2a2a2-2222-2222-2222-222222222222'),
          3, 'multi-ítem: cantidad total 3');
select ok((select product_id is null from public.sales
           where id = 'a2a2a2a2-2222-2222-2222-222222222222'),
          'multi-ítem: sin product_id directo (viven en sale_items)');
select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          5, 'multi-ítem: descuenta A (7 − 2)');
select is((select current_stock from public.products
           where id = 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd'),
          4, 'multi-ítem: descuenta B (5 − 1)');

-- ── Venta sin cliente ───────────────────────────────────────────────
select ok(
  public.create_local_sale(
    '[{"product_id":"abababab-abab-abab-abab-abababababab","quantity":1,"unit_price":50}]'::jsonb,
    null, null, 'sin cliente',
    'a3a3a3a3-3333-3333-3333-333333333333') is not null,
  'sin cliente: la venta funciona igual');
select is((select customer_id from public.sales
           where id = 'a3a3a3a3-3333-3333-3333-333333333333'),
          null::uuid, 'sin cliente: customer_id queda null');
select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          4, 'sin cliente: descuenta stock (5 − 1)');

-- ── Transaccional: sin stock suficiente NO queda nada a medias ──────
select throws_ok(
  $$select public.create_local_sale(
      '[{"product_id":"abababab-abab-abab-abab-abababababab","quantity":99,"unit_price":10}]'::jsonb)$$,
  'P0001', null, 'transaccional: pedir más que el disponible lanza excepción');
select is((select count(*)::int from public.sales where channel = 'local'),
          3, 'transaccional: la venta fallida no dejó fila');
select is((select current_stock from public.products
           where id = 'abababab-abab-abab-abab-abababababab'),
          4, 'transaccional: la venta fallida no tocó el stock');

-- Depósito sin stock del producto (el caso "depósito fantasma"): error, no
-- una venta registrada sin descuento.
insert into public.warehouses (id, profile_id, code, name)
values ('e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2',
        '44444444-4444-4444-4444-444444444444', 'DEP2', 'Depósito 2');
select throws_ok(
  $$select public.create_local_sale(
      '[{"product_id":"abababab-abab-abab-abab-abababababab","quantity":1,"unit_price":10}]'::jsonb,
      null, 'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2')$$,
  'P0001', null, 'depósito sin stock del producto: lanza excepción');

-- ── Idempotente: reintentar con el mismo id no duplica ──────────────
select is(
  public.create_local_sale(
    '[{"product_id":"cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd","quantity":1,"unit_price":50}]'::jsonb,
    null, null, 'idem',
    'a4a4a4a4-4444-4444-4444-444444444444'),
  'a4a4a4a4-4444-4444-4444-444444444444'::uuid,
  'idempotencia: primera llamada crea la venta');
select is(
  public.create_local_sale(
    '[{"product_id":"cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd","quantity":1,"unit_price":50}]'::jsonb,
    null, null, 'idem',
    'a4a4a4a4-4444-4444-4444-444444444444'),
  'a4a4a4a4-4444-4444-4444-444444444444'::uuid,
  'idempotencia: el reintento devuelve la misma venta');
select is((select count(*)::int from public.sales where channel = 'local'),
          4, 'idempotencia: no hay venta duplicada');
select is((select current_stock from public.products
           where id = 'cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd'),
          3, 'idempotencia: el stock se descontó UNA sola vez');

-- ── Validaciones restantes ──────────────────────────────────────────
select throws_ok(
  $$select public.create_local_sale(
      '[{"product_id":"abababab-abab-abab-abab-abababababab","quantity":0,"unit_price":10}]'::jsonb)$$,
  'P0001', null, 'cantidad <= 0 lanza excepción');
select throws_ok(
  $$insert into public.sales (profile_id, channel, quantity, unit_price)
    values ('44444444-4444-4444-4444-444444444444', 'ml', 1, 10)$$,
  '23514', null, 'sales: canal ml sin ml_order_id viola el check');

select * from finish();
rollback;
