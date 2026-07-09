-- pgTAP: RF-49 recalibrate_stock + compensación a cero de reconcile_order_stock
-- (cutoff pre-import: un target en 0 debe REVERTIR lo ya descontado).
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(13);

-- ── Fixtures ─────────────────────────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '77777777-7777-7777-7777-777777777777',
  'authenticated', 'authenticated', 'recalibrate@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

select public.ensure_default_warehouse('77777777-7777-7777-7777-777777777777');
select public.ensure_full_warehouse('77777777-7777-7777-7777-777777777777');

-- p1 publicado con drift (3 local, ML dice 5) · p2 roto en negativo (-9, ML 3)
-- p3 interno con stock (4 → 0) · p4 Full (local 2 → 0, espejo intacto)
-- p5 dos publicaciones (5 y 3 → max 5, no suma) · p6 pausada (ML 4)
-- p7 solo closed (6 → 0) · p8 para la compensación de reconcile
insert into public.products (id, profile_id, title) values
  ('ee110000-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', 'Publicado drift'),
  ('ee110000-0000-0000-0000-000000000002', '77777777-7777-7777-7777-777777777777', 'Roto negativo'),
  ('ee110000-0000-0000-0000-000000000003', '77777777-7777-7777-7777-777777777777', 'Interno'),
  ('ee110000-0000-0000-0000-000000000004', '77777777-7777-7777-7777-777777777777', 'Full'),
  ('ee110000-0000-0000-0000-000000000005', '77777777-7777-7777-7777-777777777777', 'Multi listing'),
  ('ee110000-0000-0000-0000-000000000006', '77777777-7777-7777-7777-777777777777', 'Pausado'),
  ('ee110000-0000-0000-0000-000000000007', '77777777-7777-7777-7777-777777777777', 'Cerrado'),
  ('ee110000-0000-0000-0000-000000000008', '77777777-7777-7777-7777-777777777777', 'Pre-import');

insert into public.ml_listings (profile_id, product_id, ml_item_id, status, available_quantity, logistic_type) values
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000001', 'MLAR1', 'active', 5, null),
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000002', 'MLAR2', 'active', 3, null),
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000004', 'MLAR4', 'active', 7, 'fulfillment'),
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000005', 'MLAR5A', 'active', 5, null),
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000005', 'MLAR5B', 'active', 3, null),
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000006', 'MLAR6', 'paused', 4, null),
  ('77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000007', 'MLAR7', 'closed', 10, null);

-- Stock previo (todo al depósito principal salvo el espejo Full).
insert into public.stock_movements (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference)
select '77777777-7777-7777-7777-777777777777', p.pid, w.id, 'on_hand', p.qty, 'initial_sync', 'ml', 'fixture'
from (values
  ('ee110000-0000-0000-0000-000000000001'::uuid,  3),
  ('ee110000-0000-0000-0000-000000000002'::uuid, -9),
  ('ee110000-0000-0000-0000-000000000003'::uuid,  4),
  ('ee110000-0000-0000-0000-000000000004'::uuid,  2),
  ('ee110000-0000-0000-0000-000000000007'::uuid,  6)
) as p(pid, qty)
join public.warehouses w
  on w.profile_id = '77777777-7777-7777-7777-777777777777' and w.is_default;

-- Espejo Full con 7 unidades (no debe tocarse).
insert into public.stock_movements (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference)
select '77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000004', w.id,
       'on_hand', 7, 'full_sync', 'ml', 'fixture-full'
from public.warehouses w
where w.profile_id = '77777777-7777-7777-7777-777777777777' and w.ml_fulfillment;

-- Σ on_hand vendible (la métrica que recalibra el RPC).
create function pg_temp.sellable(p uuid) returns bigint language sql as $$
  select coalesce(sum(ps.on_hand), 0)
    from public.product_stock ps
    join public.warehouses w on w.id = ps.warehouse_id
   where ps.product_id = p and w.is_sellable and not w.ml_fulfillment
$$;

-- ── RF-49 · recalibrate_stock ────────────────────────────────────────
select has_function('public', 'recalibrate_stock_for', array['uuid'], 'recalibrate_stock_for exists');
select has_function('public', 'recalibrate_stock', 'recalibrate_stock wrapper exists');

select is(public.recalibrate_stock_for('77777777-7777-7777-7777-777777777777'),
          7, 'primera corrida ajusta los 7 productos con drift');

select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000001'), 5::bigint,
          'publicado con drift queda en el available de ML (5)');
select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000002'), 3::bigint,
          'negativo -9 queda en el available de ML (3)');
select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000003'), 0::bigint,
          'interno sin publicación queda en 0');
select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000004'), 0::bigint,
          'producto Full: el stock local vendible queda en 0');
select is((select ps.on_hand from public.product_stock ps
             join public.warehouses w on w.id = ps.warehouse_id
            where ps.product_id = 'ee110000-0000-0000-0000-000000000004'
              and w.ml_fulfillment), 7,
          'producto Full: el espejo ML_FULL queda intacto (7)');
select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000005'), 5::bigint,
          'multi publicación usa max(available), no la suma');
select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000006'), 4::bigint,
          'publicación pausada también cuenta como target');
select is(pg_temp.sellable('ee110000-0000-0000-0000-000000000007'), 0::bigint,
          'publicación closed no cuenta: queda en 0');

select is(public.recalibrate_stock_for('77777777-7777-7777-7777-777777777777'),
          0, 'segunda corrida es no-op (idempotente)');

-- ── Cutoff pre-import · reconcile_order_stock con target 0 compensa ──
-- Orden vieja que descontó 9 de más: el target en cero la revierte.
insert into public.stock_movements (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference)
select '77777777-7777-7777-7777-777777777777', 'ee110000-0000-0000-0000-000000000008', w.id,
       'on_hand', -9, 'dispatch', 'ml', 'ORD-PRE-1'
from public.warehouses w
where w.profile_id = '77777777-7777-7777-7777-777777777777' and w.is_default;

select public.reconcile_order_stock(
  '77777777-7777-7777-7777-777777777777', 'ORD-PRE-1', null,
  '[{"product_id":"ee110000-0000-0000-0000-000000000008","reserved":0,"on_hand":0}]'::jsonb);

select is((select coalesce(sum(delta), 0) from public.stock_movements
            where reference = 'ORD-PRE-1' and bucket = 'on_hand'), 0::bigint,
          'target 0 revierte el descuento ya aplicado (Σ delta = 0)');

select * from finish();
rollback;
