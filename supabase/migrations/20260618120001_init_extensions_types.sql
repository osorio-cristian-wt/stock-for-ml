-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 01 · Extensions & enum types                                       ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- gen_random_uuid() is built into Postgres core (>= 13). pgcrypto is also
-- available in Supabase for crypt()/gen_salt() used in seeds.
create extension if not exists pgcrypto with schema extensions;

-- ── Enum types ──────────────────────────────────────────────────────
create type public.stock_reason as enum (
  'purchase', 'sale', 'adjustment', 'return', 'initial_sync'
);

create type public.ml_event_status as enum (
  'pending', 'processing', 'done', 'error'
);

create type public.alert_type as enum (
  'low_stock', 'out_of_stock', 'new_order', 'price_change'
);

-- Dollar quotes relevant for Argentina (USD purchase cost -> ARS sale price).
create type public.fx_kind as enum (
  'oficial', 'blue', 'mep', 'tarjeta', 'cripto', 'mayorista'
);

create type public.listing_status as enum (
  'active', 'paused', 'closed', 'under_review', 'inactive'
);
