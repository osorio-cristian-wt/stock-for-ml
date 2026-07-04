-- pgTAP: idempotencia para la cola offline (B1):
--  · transfer_stock v2 — p_reference del cliente: reintento = no-op
--  · apply_stock_movement v3 — p_movement_id del cliente: reintento = no-op
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(17);

-- ── Fixtures ─────────────────────────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '66666666-6666-6666-6666-666666666666',
  'authenticated', 'authenticated', 'offline-ops@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency, sale_price)
values ('33330000-0000-0000-0000-000000000001',
        '66666666-6666-6666-6666-666666666666', 'Idempotente', 5, 'USD', 300);

select public.ensure_default_warehouse('66666666-6666-6666-6666-666666666666');
insert into public.warehouses (id, profile_id, code, name, is_sellable)
values ('44440000-aaaa-aaaa-aaaa-000000000002',
        '66666666-6666-6666-6666-666666666666', 'DEP2', 'Depósito 2', true);

-- Semilla: 10 unidades en el principal.
insert into public.stock_movements (profile_id, product_id, warehouse_id, delta, reason, bucket, origin)
values ('66666666-6666-6666-6666-666666666666',
        '33330000-0000-0000-0000-000000000001',
        (select id from public.warehouses
          where profile_id = '66666666-6666-6666-6666-666666666666' and is_default),
        10, 'purchase', 'on_hand', 'user');

select is((select current_stock from public.products
           where id = '33330000-0000-0000-0000-000000000001'),
          10, 'semilla: 10 disponibles en el principal');

-- ── transfer_stock v2: p_reference del cliente ───────────────────────
select lives_ok(
  $$select public.transfer_stock(
      '33330000-0000-0000-0000-000000000001',
      (select id from public.warehouses
        where profile_id = '66666666-6666-6666-6666-666666666666' and is_default),
      '44440000-aaaa-aaaa-aaaa-000000000002', 4, null, 'ref-offline-t1')$$,
  'transfer con reference del cliente: primera vez pasa');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                  where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
          6, 'transfer: el principal quedó 10 − 4 = 6');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = '44440000-aaaa-aaaa-aaaa-000000000002'),
          4, 'transfer: DEP2 recibió 4');

-- Reintento con el MISMO reference (corte de red tras el commit) → no-op.
select lives_ok(
  $$select public.transfer_stock(
      '33330000-0000-0000-0000-000000000001',
      (select id from public.warehouses
        where profile_id = '66666666-6666-6666-6666-666666666666' and is_default),
      '44440000-aaaa-aaaa-aaaa-000000000002', 4, null, 'ref-offline-t1')$$,
  'transfer duplicado: el reintento no falla');
select is((select count(*)::int from public.stock_movements
           where reference = 'ref-offline-t1'),
          2, 'transfer duplicado: siguen siendo 2 movimientos (las 2 patas)');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                  where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
          6, 'transfer duplicado: el principal NO volvió a descontar');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = '44440000-aaaa-aaaa-aaaa-000000000002'),
          4, 'transfer duplicado: DEP2 NO volvió a sumar');

-- Sin reference (comportamiento previo) sigue funcionando.
select lives_ok(
  $$select public.transfer_stock(
      '33330000-0000-0000-0000-000000000001',
      (select id from public.warehouses
        where profile_id = '66666666-6666-6666-6666-666666666666' and is_default),
      '44440000-aaaa-aaaa-aaaa-000000000002', 1)$$,
  'transfer sin reference: sigue funcionando como antes');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                  where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
          5, 'transfer sin reference: el principal quedó 6 − 1 = 5');

-- ── apply_stock_movement v3: p_movement_id del cliente ───────────────
select is(
  public.apply_stock_movement(
    p_product_id  => '33330000-0000-0000-0000-000000000001',
    p_delta       => -2,
    p_reason      => 'adjustment',
    p_warehouse_id => (select id from public.warehouses
        where profile_id = '66666666-6666-6666-6666-666666666666' and is_default),
    p_movement_id => 'aaaa0000-0000-0000-0000-000000000001'),
  'aaaa0000-0000-0000-0000-000000000001'::uuid,
  'adjust con movement_id del cliente: devuelve ese mismo id');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                  where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
          3, 'adjust: el principal quedó 5 − 2 = 3');

-- Reintento con el MISMO movement_id → devuelve el existente, sin re-aplicar.
select is(
  public.apply_stock_movement(
    p_product_id  => '33330000-0000-0000-0000-000000000001',
    p_delta       => -2,
    p_reason      => 'adjustment',
    p_warehouse_id => (select id from public.warehouses
        where profile_id = '66666666-6666-6666-6666-666666666666' and is_default),
    p_movement_id => 'aaaa0000-0000-0000-0000-000000000001'),
  'aaaa0000-0000-0000-0000-000000000001'::uuid,
  'adjust duplicado: el reintento devuelve el mismo id');
select is((select count(*)::int from public.stock_movements
           where id = 'aaaa0000-0000-0000-0000-000000000001'),
          1, 'adjust duplicado: hay UN solo movimiento con ese id');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                  where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
          3, 'adjust duplicado: el stock NO volvió a descontar');

-- Sin movement_id (comportamiento previo) sigue funcionando.
select isnt(
  public.apply_stock_movement(
    p_product_id  => '33330000-0000-0000-0000-000000000001',
    p_delta       => -1,
    p_reason      => 'adjustment',
    p_warehouse_id => (select id from public.warehouses
        where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
  null,
  'adjust sin movement_id: genera id propio como antes');
select is((select on_hand from public.product_stock
           where product_id = '33330000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                  where profile_id = '66666666-6666-6666-6666-666666666666' and is_default)),
          2, 'adjust sin movement_id: el principal quedó 3 − 1 = 2');

select * from finish();
rollback;
