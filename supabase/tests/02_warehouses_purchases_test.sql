-- pgTAP: warehouses client RPCs (set_default_warehouse, transfer_stock) and
-- the purchase lifecycle (add_purchase_item merge, close_purchase idempotente).
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(28);

-- ── Fixtures: user + products ───────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '33333333-3333-3333-3333-333333333333',
  'authenticated', 'authenticated', 'wh-purch@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency) values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc',
   '33333333-3333-3333-3333-333333333333', 'Transfer Product', 4, 'USD'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd',
   '33333333-3333-3333-3333-333333333333', 'Purchase Product', 6, 'USD');

-- Default warehouse (PRINCIPAL) + a second one.
select public.ensure_default_warehouse('33333333-3333-3333-3333-333333333333');
insert into public.warehouses (id, profile_id, code, name)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        '33333333-3333-3333-3333-333333333333', 'DEP2', 'Depósito 2');

-- ── set_default_warehouse ───────────────────────────────────────────
select public.set_default_warehouse('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');

select is((select is_default from public.warehouses
           where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
          true, 'set_default: DEP2 pasa a ser el principal');
select is((select count(*)::int from public.warehouses
           where profile_id = '33333333-3333-3333-3333-333333333333' and is_default),
          1, 'set_default: hay exactamente un principal');
select lives_ok(
  $$select public.set_default_warehouse('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')$$,
  'set_default: repetir sobre el mismo deposito no choca con el indice unico');
select throws_ok(
  $$select public.set_default_warehouse(gen_random_uuid())$$,
  'P0001', null, 'set_default: deposito inexistente lanza excepcion');

-- Volver el principal a PRINCIPAL (las compras sin depósito caen ahí).
select public.set_default_warehouse(
  (select id from public.warehouses
    where profile_id = '33333333-3333-3333-3333-333333333333' and code = 'PRINCIPAL'));
select is((select is_default from public.warehouses
           where profile_id = '33333333-3333-3333-3333-333333333333' and code = 'PRINCIPAL'),
          true, 'set_default: se puede volver a PRINCIPAL');

-- ── transfer_stock ──────────────────────────────────────────────────
-- Semilla: +10 on_hand en PRINCIPAL.
insert into public.stock_movements (profile_id, product_id, warehouse_id, delta, reason, bucket, origin)
values ('33333333-3333-3333-3333-333333333333',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        (select id from public.warehouses
          where profile_id = '33333333-3333-3333-3333-333333333333' and code = 'PRINCIPAL'),
        10, 'purchase', 'on_hand', 'user');

select is((select current_stock from public.products
           where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
          10, 'transfer: semilla de 10 disponible');

select public.transfer_stock(
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  (select id from public.warehouses
    where profile_id = '33333333-3333-3333-3333-333333333333' and code = 'PRINCIPAL'),
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 4, 'test');

select is((select on_hand from public.product_stock ps
            join public.warehouses w on w.id = ps.warehouse_id
           where ps.product_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
             and w.code = 'PRINCIPAL'),
          6, 'transfer: origen queda con 6');
select is((select on_hand from public.product_stock
           where product_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
             and warehouse_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
          4, 'transfer: destino queda con 4');
select is((select current_stock from public.products
           where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
          10, 'transfer: balanceada entre vendibles no cambia el disponible');
select is((select count(*)::int from public.stock_movements
           where product_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
             and reason = 'transfer'),
          2, 'transfer: genera dos movimientos pareados');
select is((select count(distinct reference)::int from public.stock_movements
           where product_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
             and reason = 'transfer'),
          1, 'transfer: ambos movimientos comparten reference');
select throws_ok(
  $$select public.transfer_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 1, null)$$,
  'P0001', null, 'transfer: origen = destino lanza excepcion');
select throws_ok(
  $$select public.transfer_stock(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      (select id from public.warehouses where code = 'PRINCIPAL'
        and profile_id = '33333333-3333-3333-3333-333333333333'),
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 0, null)$$,
  'P0001', null, 'transfer: cantidad <= 0 lanza excepcion');

-- ── add_purchase_item + close_purchase ──────────────────────────────
insert into public.suppliers (id, profile_id, name)
values ('ffffffff-ffff-ffff-ffff-ffffffffffff',
        '33333333-3333-3333-3333-333333333333', 'Proveedor Test');
insert into public.purchases (id, profile_id, supplier_id)
values ('99999999-9999-9999-9999-999999999999',
        '33333333-3333-3333-3333-333333333333',
        'ffffffff-ffff-ffff-ffff-ffffffffffff');

select public.add_purchase_item(
  '99999999-9999-9999-9999-999999999999',
  'dddddddd-dddd-dddd-dddd-dddddddddddd', 2, 5.00);

select is((select quantity from public.purchase_items
           where purchase_id = '99999999-9999-9999-9999-999999999999'),
          2, 'add_item: primera linea con cantidad 2');

-- Repetir el mismo producto suma cantidades y actualiza el costo.
select public.add_purchase_item(
  '99999999-9999-9999-9999-999999999999',
  'dddddddd-dddd-dddd-dddd-dddddddddddd', 3, 7.50);

select is((select count(*)::int from public.purchase_items
           where purchase_id = '99999999-9999-9999-9999-999999999999'),
          1, 'add_item: el producto repetido no duplica la linea');
select is((select quantity from public.purchase_items
           where purchase_id = '99999999-9999-9999-9999-999999999999'),
          5, 'add_item: cantidades sumadas (2+3)');
select is((select unit_cost from public.purchase_items
           where purchase_id = '99999999-9999-9999-9999-999999999999'),
          7.50::numeric(14,2), 'add_item: costo actualizado al ultimo');
select throws_ok(
  $$select public.add_purchase_item(
      '99999999-9999-9999-9999-999999999999',
      'dddddddd-dddd-dddd-dddd-dddddddddddd', 0, null)$$,
  'P0001', null, 'add_item: cantidad <= 0 lanza excepcion');

select public.close_purchase('99999999-9999-9999-9999-999999999999');

select is((select status from public.purchases
           where id = '99999999-9999-9999-9999-999999999999'),
          'closed'::public.purchase_status, 'close: estado closed');
select ok((select purchased_at is not null from public.purchases
           where id = '99999999-9999-9999-9999-999999999999'),
          'close: purchased_at seteado');
select is((select total from public.purchases
           where id = '99999999-9999-9999-9999-999999999999'),
          37.50::numeric(14,2), 'close: total recalculado (5 x 7.50)');
select is((select current_stock from public.products
           where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
          5, 'close: el stock disponible sube a 5');
select is((select on_hand from public.product_stock ps
            join public.warehouses w on w.id = ps.warehouse_id
           where ps.product_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
             and w.code = 'PRINCIPAL'),
          5, 'close: sin deposito elegido impacta en el principal');
select is((select count(*)::int from public.stock_movements
           where reference = '99999999-9999-9999-9999-999999999999'
             and reason = 'purchase'),
          1, 'close: un movimiento por linea con reference = compra');

-- Idempotencia: cerrar de nuevo no repite movimientos ni cambia el total.
select lives_ok(
  $$select public.close_purchase('99999999-9999-9999-9999-999999999999')$$,
  'close: re-cerrar es un no-op');
select is((select count(*)::int from public.stock_movements
           where reference = '99999999-9999-9999-9999-999999999999'),
          1, 'close: re-cerrar no duplica movimientos');
select is((select current_stock from public.products
           where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'),
          5, 'close: re-cerrar no vuelve a sumar stock');
select throws_ok(
  $$select public.add_purchase_item(
      '99999999-9999-9999-9999-999999999999',
      'dddddddd-dddd-dddd-dddd-dddddddddddd', 1, null)$$,
  'P0001', null, 'add_item: sobre una compra cerrada lanza excepcion');

select * from finish();
rollback;
