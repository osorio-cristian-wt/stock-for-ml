-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 08 · Stock states — tables & columns                               ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ── Warehouses (depósitos / ubicaciones físicas) ────────────────────
create table public.warehouses (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  code        text not null,
  name        text not null,
  is_default  boolean not null default false,  -- depósito de despacho por defecto
  is_sellable boolean not null default true,   -- cuenta para el available publicado a ML
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (profile_id, code)
);
-- A single default warehouse per profile.
create unique index warehouses_one_default_idx
  on public.warehouses (profile_id) where is_default;

-- ── Per-(product, warehouse) stock, maintained by trigger ───────────
create table public.product_stock (
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  product_id   uuid not null references public.products(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  incoming     int not null default 0,
  on_hand      int not null default 0,
  reserved     int not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (product_id, warehouse_id)
);
create index product_stock_profile_idx on public.product_stock (profile_id);
comment on table public.product_stock is
  'Derived from stock_movements. available = on_hand - reserved (sellable warehouses).';

-- ── ML push queue: products whose available changed by user/system ──
--    (drained by the push-stock Edge Function). SENSITIVE: service_role only.
create table public.stock_push_queue (
  product_id  uuid primary key references public.products(id) on delete cascade,
  status      public.ml_event_status not null default 'pending',
  attempts    int not null default 0,
  enqueued_at timestamptz not null default now(),
  processed_at timestamptz,
  error       text
);

-- ── Internal product categories (taxonomy del usuario) ──────────────
create table public.product_categories (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  parent_id  uuid references public.product_categories(id) on delete set null,
  name       text not null,
  slug       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, slug)
);

-- ── New columns on existing tables ──────────────────────────────────
-- stock_movements: warehouse + bucket + origin (defaults keep old inserts valid:
-- a naive insert lands as an on_hand, user-origin movement in the default depot).
alter table public.stock_movements
  add column warehouse_id uuid references public.warehouses(id),
  add column bucket public.stock_bucket not null default 'on_hand',
  add column origin public.stock_origin not null default 'user';
create index stock_movements_reference_idx
  on public.stock_movements (reference, product_id, bucket);

-- products: barcode (global) + internal category + brand.
alter table public.products
  add column gtin        text,
  add column category_id uuid references public.product_categories(id) on delete set null,
  add column brand       text;
create unique index products_gtin_uidx
  on public.products (profile_id, gtin) where gtin is not null;
create index products_category_idx on public.products (profile_id, category_id);
create index products_brand_idx    on public.products (profile_id, brand);

-- sales: fulfillment lifecycle + dispatch warehouse.
alter table public.sales
  add column fulfillment_status public.fulfillment_status,
  add column warehouse_id uuid references public.warehouses(id);

-- ml_listings: link to the ML catalog product matched by GTIN + the GTIN itself.
alter table public.ml_listings
  add column catalog_product_id text,
  add column gtin text;
