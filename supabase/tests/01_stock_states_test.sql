-- pgTAP: two-phase stock + idempotent order reconciliation (the broken scenarios).
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(13);

-- ── Fixtures: user + product ────────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '22222222-2222-2222-2222-222222222222',
  'authenticated', 'authenticated', 'recon@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '22222222-2222-2222-2222-222222222222', 'Recon Product', 5, 'USD');

-- Initial stock: +10 on_hand (user origin) -> creates default warehouse + queue.
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('22222222-2222-2222-2222-222222222222',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 10, 'purchase', 'on_hand', 'user');

select is((select current_stock from public.products where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          10, 'initial on_hand 10 => available 10');
select is((select count(*)::int from public.stock_push_queue
           where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          1, 'user-origin movement enqueues an ML push');

-- From here, prove ML-origin reconciles NEVER enqueue: clear the queue.
delete from public.stock_push_queue where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

-- ── Venta normal: paid order reserves 1 ─────────────────────────────
select public.reconcile_order_stock(
  '22222222-2222-2222-2222-222222222222', 'ORD-1', null,
  '[{"product_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","reserved":1,"on_hand":0}]'::jsonb);

select is((select reserved from public.product_stock where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          1, 'venta: reserved = 1');
select is((select current_stock from public.products where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          9, 'venta: available = 9');

-- ── Doble notificación: idempotente ─────────────────────────────────
select public.reconcile_order_stock(
  '22222222-2222-2222-2222-222222222222', 'ORD-1', null,
  '[{"product_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","reserved":1,"on_hand":0}]'::jsonb);

select is((select reserved from public.product_stock where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          1, 'doble notificacion: reserved sigue 1 (idempotente)');
select is((select count(*)::int from public.stock_movements
           where reference = 'ORD-1' and bucket = 'reserved'),
          1, 'doble notificacion: un solo movimiento reserved');

-- ── Cancelada DESPUÉS de descontar: revierte ────────────────────────
select public.reconcile_order_stock(
  '22222222-2222-2222-2222-222222222222', 'ORD-1', null,
  '[{"product_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","reserved":0,"on_hand":0}]'::jsonb);

select is((select reserved from public.product_stock where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          0, 'cancelada despues: reserved revertido a 0');
select is((select current_stock from public.products where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          10, 'cancelada despues: available restaurado a 10');

-- ── Cancelada ANTES de descontar: no descuenta ──────────────────────
select public.reconcile_order_stock(
  '22222222-2222-2222-2222-222222222222', 'ORD-2', null,
  '[{"product_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","reserved":0,"on_hand":0}]'::jsonb);

select is((select count(*)::int from public.stock_movements where reference = 'ORD-2'),
          0, 'cancelada antes: no se crea ningun movimiento');

-- ── Despacho: reserved -> on_hand consumido ─────────────────────────
select public.reconcile_order_stock(
  '22222222-2222-2222-2222-222222222222', 'ORD-3', null,
  '[{"product_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","reserved":1,"on_hand":0}]'::jsonb);
select public.reconcile_order_stock(
  '22222222-2222-2222-2222-222222222222', 'ORD-3', null,
  '[{"product_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","reserved":0,"on_hand":-1}]'::jsonb);

select is((select on_hand from public.product_stock where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          9, 'despacho: on_hand = 9');
select is((select reserved from public.product_stock where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          0, 'despacho: reserved liberado');
select is((select current_stock from public.products where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          9, 'despacho: available = 9');

-- ── Anti-loop: ningún reconcile (origin=ml) encoló un push ──────────
select is((select count(*)::int from public.stock_push_queue
           where product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
          0, 'eventos de ML no empujan a ML (cola vacia)');

select * from finish();
rollback;
