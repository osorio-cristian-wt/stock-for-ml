-- pgTAP: lote operativo 2026-07-03 (2):
--  · create_local_sale v3 — depósito POR LÍNEA + validación agrupada
--  · reconcile_order_stock v2 — reserva/despacho repartido entre depósitos
--  · product_cost_ars — costeo por política (fifo / avg / last / manual)
--  · v_sale_profit — ganancia real de una venta
--  · tg_check_low_stock v2 — alerta al crear/subir umbral, silencio al reponer
-- Run with:  supabase test db
create extension if not exists pgtap with schema extensions;
set search_path to extensions, public;

begin;
select plan(34);

-- ── Fixtures ─────────────────────────────────────────────────────────
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '55555555-5555-5555-5555-555555555555',
  'authenticated', 'authenticated', 'sale-ops@stockforml.dev', 'x',
  now(), '{"provider":"email"}', '{}', now(), now(), '', '', '', ''
);

insert into public.products (id, profile_id, title, purchase_cost, purchase_currency, sale_price) values
  ('11110000-0000-0000-0000-000000000001',
   '55555555-5555-5555-5555-555555555555', 'Multi depósito', 5, 'USD', 300),
  ('11110000-0000-0000-0000-000000000002',
   '55555555-5555-5555-5555-555555555555', 'Orden ML', 5, 'USD', 300),
  ('11110000-0000-0000-0000-000000000003',
   '55555555-5555-5555-5555-555555555555', 'Costeado', 999, 'ARS', 300);

select public.ensure_default_warehouse('55555555-5555-5555-5555-555555555555');
insert into public.warehouses (id, profile_id, code, name, is_sellable)
values ('22220000-aaaa-aaaa-aaaa-000000000002',
        '55555555-5555-5555-5555-555555555555', 'DEP2', 'Depósito 2', true);

-- P1: 5 en principal + 5 en DEP2. P2: 2 en principal + 3 en DEP2.
insert into public.stock_movements (profile_id, product_id, warehouse_id, delta, reason, bucket, origin)
select '55555555-5555-5555-5555-555555555555', p, w, q, 'purchase', 'on_hand', 'user'
from (values
  ('11110000-0000-0000-0000-000000000001'::uuid,
   (select id from public.warehouses where profile_id = '55555555-5555-5555-5555-555555555555' and is_default), 5),
  ('11110000-0000-0000-0000-000000000001'::uuid,
   '22220000-aaaa-aaaa-aaaa-000000000002'::uuid, 5),
  ('11110000-0000-0000-0000-000000000002'::uuid,
   (select id from public.warehouses where profile_id = '55555555-5555-5555-5555-555555555555' and is_default), 2),
  ('11110000-0000-0000-0000-000000000002'::uuid,
   '22220000-aaaa-aaaa-aaaa-000000000002'::uuid, 3)
) v(p, w, q);

select is((select current_stock from public.products
           where id = '11110000-0000-0000-0000-000000000001'),
          10, 'semilla: P1 con 10 disponibles entre dos depósitos');

-- ── create_local_sale v3: depósito por línea ─────────────────────────
select is(
  public.create_local_sale(
    format('[{"product_id":"11110000-0000-0000-0000-000000000001","quantity":3,"unit_price":100,"warehouse_id":"%s"},
             {"product_id":"11110000-0000-0000-0000-000000000001","quantity":4,"unit_price":120,"warehouse_id":"22220000-aaaa-aaaa-aaaa-000000000002"}]',
           (select id from public.warehouses where profile_id = '55555555-5555-5555-5555-555555555555' and is_default))::jsonb,
    null, null, 'multi depósito',
    'b1b10000-0000-0000-0000-000000000001'),
  'b1b10000-0000-0000-0000-000000000001'::uuid,
  'multi-depósito: una venta saca de DOS depósitos');

select is((select count(*)::int from public.sale_items
           where sale_id = 'b1b10000-0000-0000-0000-000000000001'),
          2, 'multi-depósito: una línea por (producto, depósito)');
select is((select total_amount from public.sales
           where id = 'b1b10000-0000-0000-0000-000000000001'),
          780.00::numeric(14,2), 'multi-depósito: total 3×100 + 4×120');
select is((select on_hand from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000001'
             and warehouse_id = (select id from public.warehouses
                                  where profile_id = '55555555-5555-5555-5555-555555555555' and is_default)),
          2, 'multi-depósito: el principal quedó 5 − 3 = 2');
select is((select on_hand from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000001'
             and warehouse_id = '22220000-aaaa-aaaa-aaaa-000000000002'),
          1, 'multi-depósito: DEP2 quedó 5 − 4 = 1');
select is((select current_stock from public.products
           where id = '11110000-0000-0000-0000-000000000001'),
          3, 'multi-depósito: disponible total 3');

-- Validación AGRUPADA: dos líneas del mismo (producto, depósito) que juntas
-- exceden el disponible deben fallar aunque cada una alcance por separado.
select throws_ok(
  format($j$select public.create_local_sale(
    '[{"product_id":"11110000-0000-0000-0000-000000000001","quantity":1,"unit_price":10,"warehouse_id":"%s"},
      {"product_id":"11110000-0000-0000-0000-000000000001","quantity":2,"unit_price":10,"warehouse_id":"%s"}]'::jsonb)$j$,
    (select id from public.warehouses where profile_id = '55555555-5555-5555-5555-555555555555' and is_default),
    (select id from public.warehouses where profile_id = '55555555-5555-5555-5555-555555555555' and is_default)),
  'P0001', null,
  'validación agrupada: 1+2 sobre 2 disponibles en el mismo depósito falla');

-- ── reconcile_order_stock v2: reparto entre depósitos vendibles ──────
-- Reserva de 4 unidades de P2 (2 en principal + 3 en DEP2).
select lives_ok(
  $$select public.reconcile_order_stock(
      '55555555-5555-5555-5555-555555555555', 'ORD-1', null,
      '[{"product_id":"11110000-0000-0000-0000-000000000002","reserved":4,"on_hand":0}]'::jsonb)$$,
  'reconcile: reservar 4 con 2+3 disponibles no falla');
select is((select reserved from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'
             and warehouse_id = (select id from public.warehouses
                                  where profile_id = '55555555-5555-5555-5555-555555555555' and is_default)),
          2, 'reconcile: reserva 2 en el principal (hasta su disponible)');
select is((select reserved from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'
             and warehouse_id = '22220000-aaaa-aaaa-aaaa-000000000002'),
          2, 'reconcile: el resto (2) se reserva en DEP2');
select is((select current_stock from public.products
           where id = '11110000-0000-0000-0000-000000000002'),
          1, 'reconcile: disponible publicable = 5 − 4 reservadas');

-- Despacho: la orden pasa a shipped → libera reservas y descuenta físico
-- EN LOS MISMOS depósitos donde estaba reservado.
select lives_ok(
  $$select public.reconcile_order_stock(
      '55555555-5555-5555-5555-555555555555', 'ORD-1', null,
      '[{"product_id":"11110000-0000-0000-0000-000000000002","reserved":0,"on_hand":-4}]'::jsonb)$$,
  'reconcile: despacho de la orden no falla');
select is((select coalesce(sum(reserved), 0)::int from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'),
          0, 'despacho: no queda nada reservado');
select is((select on_hand from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'
             and warehouse_id = (select id from public.warehouses
                                  where profile_id = '55555555-5555-5555-5555-555555555555' and is_default)),
          0, 'despacho: el principal despachó sus 2');
select is((select on_hand from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'
             and warehouse_id = '22220000-aaaa-aaaa-aaaa-000000000002'),
          1, 'despacho: DEP2 despachó 2 y le queda 1');

-- Cancelación tardía (post-despacho): el físico vuelve a los depósitos
-- desde donde salió.
select lives_ok(
  $$select public.reconcile_order_stock(
      '55555555-5555-5555-5555-555555555555', 'ORD-1', null,
      '[{"product_id":"11110000-0000-0000-0000-000000000002","reserved":0,"on_hand":0}]'::jsonb)$$,
  'reconcile: cancelación tardía no falla');
select is((select on_hand from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'
             and warehouse_id = (select id from public.warehouses
                                  where profile_id = '55555555-5555-5555-5555-555555555555' and is_default)),
          2, 'cancelación: el principal recupera sus 2');
select is((select on_hand from public.product_stock
           where product_id = '11110000-0000-0000-0000-000000000002'
             and warehouse_id = '22220000-aaaa-aaaa-aaaa-000000000002'),
          3, 'cancelación: DEP2 recupera sus 2');

-- ── Costeo por política ──────────────────────────────────────────────
-- Dos compras ARS cerradas: 10 @ $100 (vieja) y 10 @ $200 (nueva).
insert into public.purchases (id, profile_id, status, currency, purchased_at) values
  ('cccc0000-0000-0000-0000-000000000001',
   '55555555-5555-5555-5555-555555555555', 'closed', 'ARS', now() - interval '2 days'),
  ('cccc0000-0000-0000-0000-000000000002',
   '55555555-5555-5555-5555-555555555555', 'closed', 'ARS', now() - interval '1 day');
insert into public.purchase_items (profile_id, purchase_id, product_id, quantity, unit_cost) values
  ('55555555-5555-5555-5555-555555555555', 'cccc0000-0000-0000-0000-000000000001',
   '11110000-0000-0000-0000-000000000003', 10, 100),
  ('55555555-5555-5555-5555-555555555555', 'cccc0000-0000-0000-0000-000000000002',
   '11110000-0000-0000-0000-000000000003', 10, 200);
-- El stock físico correspondiente (20 unidades al principal).
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('55555555-5555-5555-5555-555555555555',
        '11110000-0000-0000-0000-000000000003', 20, 'purchase', 'on_hand', 'user');

select is(public.product_cost_ars('11110000-0000-0000-0000-000000000003', 'fifo'),
          100.00::numeric, 'fifo sin consumo: manda la capa más vieja ($100)');
select is(public.product_cost_ars('11110000-0000-0000-0000-000000000003', 'avg'),
          150.00::numeric, 'avg: promedio ponderado $150');
select is(public.product_cost_ars('11110000-0000-0000-0000-000000000003', 'last'),
          200.00::numeric, 'last: la compra más reciente $200');
select is(public.product_cost_ars('11110000-0000-0000-0000-000000000003', 'manual'),
          999.00::numeric, 'manual: el costo cargado en el producto (ARS)');

-- Vender 15 consume toda la capa de $100 → FIFO pasa a la capa de $200.
select ok(
  public.create_local_sale(
    '[{"product_id":"11110000-0000-0000-0000-000000000003","quantity":15,"unit_price":300}]'::jsonb,
    null, null, 'consume capa 1',
    'b1b10000-0000-0000-0000-000000000003') is not null,
  'costeo: venta de 15 para consumir la primera capa');
select is(public.product_cost_ars('11110000-0000-0000-0000-000000000003', 'fifo'),
          200.00::numeric, 'fifo tras consumir 15: capa vigente $200');

-- Ganancia real de esa venta con política avg (app_settings del perfil).
insert into public.app_settings (profile_id, cost_policy)
values ('55555555-5555-5555-5555-555555555555', 'avg')
on conflict (profile_id) do update set cost_policy = 'avg';
select is((select gross from public.v_sale_profit
           where sale_id = 'b1b10000-0000-0000-0000-000000000003'),
          4500.00::numeric, 'v_sale_profit: bruto 15 × $300');
select is((select cost_ars from public.v_sale_profit
           where sale_id = 'b1b10000-0000-0000-0000-000000000003'),
          2250.00::numeric, 'v_sale_profit: COGS 15 × $150 (avg)');
select is((select net_profit from public.v_sale_profit
           where sale_id = 'b1b10000-0000-0000-0000-000000000003'),
          2250.00::numeric, 'v_sale_profit: ganancia = bruto − COGS');

-- ── Alertas de stock bajo v2 ─────────────────────────────────────────
-- Producto que NACE bajo el umbral → alerta inmediata (antes: nunca).
insert into public.products (id, profile_id, title, low_stock_threshold) values
  ('11110000-0000-0000-0000-000000000004',
   '55555555-5555-5555-5555-555555555555', 'Umbralado', 5);
select ok(
  exists(select 1 from public.alerts
          where product_id = '11110000-0000-0000-0000-000000000004'
            and type = 'out_of_stock' and is_read = false),
  'alerta: producto creado en 0 alerta sin necesitar un movimiento');

-- Sube a 2 (SUBIDA de stock, sigue bajo el umbral 5) → alerta low_stock.
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('55555555-5555-5555-5555-555555555555',
        '11110000-0000-0000-0000-000000000004', 2, 'purchase', 'on_hand', 'user');
select ok(
  exists(select 1 from public.alerts
          where product_id = '11110000-0000-0000-0000-000000000004'
            and type = 'low_stock' and is_read = false and current_qty = 2),
  'alerta: cargar 2 con umbral 5 alerta aunque el stock haya SUBIDO');

-- Se repone por encima del umbral → las alertas sin leer se silencian solas.
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('55555555-5555-5555-5555-555555555555',
        '11110000-0000-0000-0000-000000000004', 10, 'purchase', 'on_hand', 'user');
select is((select count(*)::int from public.alerts
           where product_id = '11110000-0000-0000-0000-000000000004'
             and is_read = false),
          0, 'alerta: reponer por encima del umbral marca leídas las pendientes');

-- Subir el umbral por encima del stock actual (12) también alerta.
update public.products set low_stock_threshold = 20
 where id = '11110000-0000-0000-0000-000000000004';
select ok(
  exists(select 1 from public.alerts
          where product_id = '11110000-0000-0000-0000-000000000004'
            and type = 'low_stock' and is_read = false and threshold = 20),
  'alerta: cambiar el umbral re-evalúa sin necesidad de mover stock');

-- No spamea: otra baja dentro del umbral con alerta sin leer no duplica.
insert into public.stock_movements (profile_id, product_id, delta, reason, bucket, origin)
values ('55555555-5555-5555-5555-555555555555',
        '11110000-0000-0000-0000-000000000004', -1, 'adjustment', 'on_hand', 'user');
select is((select count(*)::int from public.alerts
           where product_id = '11110000-0000-0000-0000-000000000004'
             and type = 'low_stock' and is_read = false),
          1, 'alerta: sin duplicados mientras la anterior siga sin leer');

-- ── sale_price persiste ──────────────────────────────────────────────
select is((select sale_price from public.products
           where id = '11110000-0000-0000-0000-000000000001'),
          300.00::numeric(14,2), 'products.sale_price: la columna nueva persiste');

select * from finish();
rollback;
