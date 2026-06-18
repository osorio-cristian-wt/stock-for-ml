-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ Seed data for LOCAL development & tests                            ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Creates one owner user (owner@stockforml.dev / password123). The
-- on_auth_user_created trigger auto-creates its profile + app_settings.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'owner@stockforml.dev',
  extensions.crypt('password123', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Owner"}',
  now(), now(), '', '', '', ''
) on conflict (id) do nothing;

insert into auth.identities (
  id, provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  '{"sub":"00000000-0000-0000-0000-000000000001","email":"owner@stockforml.dev"}',
  'email', now(), now(), now()
) on conflict (provider_id, provider) do nothing;

-- ── FX rate (USD -> ARS, blue) ──────────────────────────────────────
insert into public.fx_rates (base_currency, quote_currency, kind, buy, sell, rate, source)
values ('USD', 'ARS', 'blue', 1180, 1200, 1200, 'seed');

-- ── Products ────────────────────────────────────────────────────────
insert into public.products (id, profile_id, sku, title, purchase_cost, purchase_currency)
values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 'SKU-001', 'Auriculares Bluetooth', 8.50, 'USD'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001', 'SKU-002', 'Cargador 20W USB-C', 4.00, 'USD')
on conflict do nothing;

-- ── Initial stock (trigger maintains products.current_stock) ────────
insert into public.stock_movements (profile_id, product_id, delta, reason, note)
values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 10, 'initial_sync', 'carga inicial'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 3,  'initial_sync', 'carga inicial');

-- ── ML listings linked to products ──────────────────────────────────
insert into public.ml_listings (
  profile_id, product_id, ml_item_id, title, category_id, listing_type_id,
  price, currency_id, available_quantity, est_sale_fee, status
) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'MLA111111111', 'Auriculares Bluetooth', 'MLA1055', 'gold_special', 25000, 'ARS', 10, 3000, 'active'),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 'MLA222222222', 'Cargador 20W USB-C',    'MLA1000', 'gold_special', 12000, 'ARS', 3,  1500, 'active')
on conflict do nothing;
