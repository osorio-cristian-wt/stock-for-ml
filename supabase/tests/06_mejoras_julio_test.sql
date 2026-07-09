-- pgTAP: mejoras julio 2026 (fase A + import_jobs):
--  · sale_charges (RF-39) — v_sale_profit descuenta los cargos tipados
--  · has_cost (RF-40) — sin costo ⇒ net_profit/markup/margen NULL
--  · Full (ML) (RF-38) — espejo read-only, atribución de ingreso sin push
--  · import_jobs (RF-36) — tabla + RLS de solo lectura
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(26);

-- ── Fixtures ─────────────────────────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '66666666-6666-6666-6666-666666666666',
  'authenticated', 'authenticated', 'julio@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

-- Producto CON costo manual en ARS (policy manual para no depender de compras).
-- (upsert: el trigger de alta de usuario ya crea la fila de app_settings)
insert into public.app_settings (profile_id, cost_policy)
values ('66666666-6666-6666-6666-666666666666', 'manual')
on conflict (profile_id) do update set cost_policy = 'manual';
insert into public.products (id, profile_id, title, purchase_cost, purchase_currency)
values ('cc110000-0000-0000-0000-000000000001',
        '66666666-6666-6666-6666-666666666666', 'Con costo', 4000, 'ARS');
-- Producto SIN costo.
insert into public.products (id, profile_id, title, purchase_cost, purchase_currency)
values ('cc110000-0000-0000-0000-000000000002',
        '66666666-6666-6666-6666-666666666666', 'Sin costo', 0, 'ARS');

-- ── RF-39 · sale_charges en v_sale_profit ───────────────────────────
select has_table('public', 'sale_charges', 'sale_charges table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.sale_charges'::regclass),
          'RLS enabled on sale_charges');

insert into public.sales (id, profile_id, ml_order_id, product_id, quantity,
                          unit_price, sale_fee, shipping_cost, total_amount, status)
values ('dd110000-0000-0000-0000-000000000001',
        '66666666-6666-6666-6666-666666666666', 'ORD-CH-1',
        'cc110000-0000-0000-0000-000000000001', 1, 10000, 100, 50, 10000, 'paid');

-- Sin cargos: cae al legacy sale_fee + shipping_cost.
select is((select charges_ars from public.v_sale_profit
           where sale_id = 'dd110000-0000-0000-0000-000000000001'),
          150.00::numeric, 'sin cargos: charges = sale_fee + shipping (legacy)');

insert into public.sale_charges (profile_id, sale_id, kind, amount, source) values
  ('66666666-6666-6666-6666-666666666666', 'dd110000-0000-0000-0000-000000000001', 'commission', 1300, 'order'),
  ('66666666-6666-6666-6666-666666666666', 'dd110000-0000-0000-0000-000000000001', 'shipping',   800,  'shipment'),
  ('66666666-6666-6666-6666-666666666666', 'dd110000-0000-0000-0000-000000000001', 'tax',        200,  'order');

select is((select charges_ars from public.v_sale_profit
           where sale_id = 'dd110000-0000-0000-0000-000000000001'),
          2300.00::numeric, 'con cargos: charges = Σ sale_charges (no el legacy)');
-- net = 10000 − 2300 − 4000 (costo manual) = 3700
select is((select net_profit from public.v_sale_profit
           where sale_id = 'dd110000-0000-0000-0000-000000000001'),
          3700.00::numeric, 'net = bruto − cargos − COGS');
select is((select has_full_cost from public.v_sale_profit
           where sale_id = 'dd110000-0000-0000-0000-000000000001'),
          true, 'venta con costo: has_full_cost');

-- ── RF-40 · sin costo ⇒ profit NULL ─────────────────────────────────
insert into public.sales (id, profile_id, ml_order_id, product_id, quantity,
                          unit_price, sale_fee, shipping_cost, total_amount, status)
values ('dd110000-0000-0000-0000-000000000002',
        '66666666-6666-6666-6666-666666666666', 'ORD-CH-2',
        'cc110000-0000-0000-0000-000000000002', 2, 5000, 0, 0, 10000, 'paid');

select is((select has_full_cost from public.v_sale_profit
           where sale_id = 'dd110000-0000-0000-0000-000000000002'),
          false, 'venta sin costo: has_full_cost = false');
select is((select net_profit from public.v_sale_profit
           where sale_id = 'dd110000-0000-0000-0000-000000000002'),
          null::numeric, 'venta sin costo: net_profit NULL (antes: inflado)');

insert into public.ml_listings (id, profile_id, product_id, ml_item_id, price, est_sale_fee)
values ('ee110000-0000-0000-0000-000000000001',
        '66666666-6666-6666-6666-666666666666',
        'cc110000-0000-0000-0000-000000000001', 'MLACOST', 9000, 900),
       ('ee110000-0000-0000-0000-000000000002',
        '66666666-6666-6666-6666-666666666666',
        'cc110000-0000-0000-0000-000000000002', 'MLANOCOST', 9000, 900);

select is((select has_cost from public.v_product_economics where ml_item_id = 'MLACOST'),
          true, 'economics: producto con costo => has_cost');
-- 9000 − 900 − 4000 = 4100
select is((select net_profit from public.v_product_economics where ml_item_id = 'MLACOST'),
          4100.00::numeric, 'economics: net_profit con costo');
select is((select has_cost from public.v_product_economics where ml_item_id = 'MLANOCOST'),
          false, 'economics: sin costo => has_cost = false');
select is((select net_profit from public.v_product_economics where ml_item_id = 'MLANOCOST'),
          null::numeric, 'economics: sin costo => net_profit NULL');
select is((select markup_pct from public.v_product_economics where ml_item_id = 'MLANOCOST'),
          null::numeric, 'economics: sin costo => markup NULL');

-- ── RF-38 · depósito Full espejo ─────────────────────────────────────
select is(public.ensure_full_warehouse('66666666-6666-6666-6666-666666666666'),
          public.ensure_full_warehouse('66666666-6666-6666-6666-666666666666'),
          'ensure_full_warehouse es idempotente');
select is((select is_sellable from public.warehouses
           where profile_id = '66666666-6666-6666-6666-666666666666' and ml_fulfillment),
          false, 'el depósito Full no es vendible');

-- Stock local previo: 10 unidades en el depósito principal (user => push).
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('66666666-6666-6666-6666-666666666666',
        'cc110000-0000-0000-0000-000000000001', 10, 'purchase', 'on_hand', 'user');
delete from public.stock_push_queue
 where product_id = 'cc110000-0000-0000-0000-000000000001';

-- Espejo inicial sin tracking (import): Full reporta 5.
select is(public.reconcile_full_stock('66666666-6666-6666-6666-666666666666',
          'cc110000-0000-0000-0000-000000000001', 5, 'MLACOST', false),
          5, 'espejo Full: delta +5');
select is((select count(*)::int from public.full_inbounds
           where product_id = 'cc110000-0000-0000-0000-000000000001'),
          0, 'sin tracking: no genera ingreso a atribuir');
-- El Full NO cuenta para el disponible publicado (no vendible): sigue 10.
select is((select current_stock from public.products
           where id = 'cc110000-0000-0000-0000-000000000001'),
          10, 'available excluye el depósito Full');

-- Mercadería nueva detectada (5 → 8) CON tracking ⇒ ingreso pendiente de 3.
select is(public.reconcile_full_stock('66666666-6666-6666-6666-666666666666',
          'cc110000-0000-0000-0000-000000000001', 8, 'MLACOST', true),
          3, 'espejo Full: delta +3');
select is((select qty from public.full_inbounds
           where product_id = 'cc110000-0000-0000-0000-000000000001' and status = 'pending'),
          3, 'ingreso a Full de 3 pendiente de atribuir');
-- Idempotente: mismo qty ⇒ delta 0, sin ingreso nuevo.
select is(public.reconcile_full_stock('66666666-6666-6666-6666-666666666666',
          'cc110000-0000-0000-0000-000000000001', 8, 'MLACOST', true),
          0, 'espejo Full: sin cambios => delta 0');

-- Atribuir el ingreso al depósito principal: descuenta local SIN push.
select public.attribute_full_inbound(
  (select id from public.full_inbounds
    where product_id = 'cc110000-0000-0000-0000-000000000001' and status = 'pending'),
  (select id from public.warehouses
    where profile_id = '66666666-6666-6666-6666-666666666666' and is_default));

select is((select on_hand from public.product_stock ps
            join public.warehouses w on w.id = ps.warehouse_id
           where ps.product_id = 'cc110000-0000-0000-0000-000000000001' and w.is_default),
          7, 'atribución: descuenta 3 del depósito local');
select is((select count(*)::int from public.stock_push_queue
           where product_id = 'cc110000-0000-0000-0000-000000000001'),
          0, 'atribución: NO encola push a ML (origin=ml)');
select is((select count(*)::int from public.full_inbounds
           where product_id = 'cc110000-0000-0000-0000-000000000001' and status = 'pending'),
          0, 'atribución: el ingreso queda resuelto');

-- ── RF-36 · import_jobs ──────────────────────────────────────────────
select has_table('public', 'import_jobs', 'import_jobs table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.import_jobs'::regclass),
          'RLS enabled on import_jobs');

select * from finish();
rollback;
