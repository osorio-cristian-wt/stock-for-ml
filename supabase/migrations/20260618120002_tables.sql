-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 02 · Tables                                                        ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ── Profile (1 row per app user; single-user today, multi-tenant ready) ──
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.profiles is 'App user profile, 1:1 with auth.users.';

-- ── Per-user settings ───────────────────────────────────────────────
create table public.app_settings (
  profile_id               uuid primary key references public.profiles(id) on delete cascade,
  low_stock_threshold      int  not null default 1 check (low_stock_threshold >= 0),
  fx_kind                  public.fx_kind not null default 'blue',
  default_purchase_currency text not null default 'USD',
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

-- ── MercadoLibre account linked to a profile ────────────────────────
create table public.ml_accounts (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  ml_user_id   bigint not null,
  nickname     text,
  site_id      text not null default 'MLA',
  connected_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (profile_id, ml_user_id)
);

-- ── ML OAuth tokens — SENSITIVE. RLS denies all to clients; only the ──
--    service_role (Edge Functions) may read/write (bypasses RLS).
create table public.ml_credentials (
  ml_account_id uuid primary key references public.ml_accounts(id) on delete cascade,
  access_token  text not null,
  refresh_token text not null,
  token_type    text not null default 'bearer',
  scope         text,
  expires_at    timestamptz not null,
  updated_at    timestamptz not null default now()
);
comment on table public.ml_credentials is 'ML OAuth tokens. service_role only.';

-- ── OAuth PKCE state (short-lived). SENSITIVE: service_role only. ────
create table public.oauth_states (
  state         text primary key,
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  code_verifier text not null,
  redirect_uri  text,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '15 minutes')
);

-- ── Products (internal catalog; may or may not be published on ML) ───
create table public.products (
  id                      uuid primary key default gen_random_uuid(),
  profile_id              uuid not null references public.profiles(id) on delete cascade,
  sku                     text,
  title                   text not null,
  description             text,
  purchase_cost           numeric(14,2) not null default 0 check (purchase_cost >= 0),
  purchase_currency       text not null default 'USD',
  purchase_includes_taxes boolean not null default false,
  image_url               text,
  current_stock           int  not null default 0,  -- denormalized from stock_movements
  low_stock_threshold     int,                       -- overrides app_settings when set
  is_active               boolean not null default true,
  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (profile_id, sku)
);
comment on column public.products.current_stock is 'Maintained by trigger from stock_movements.';

-- ── ML listings (publications). Linked to an internal product. ──────
create table public.ml_listings (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles(id) on delete cascade,
  product_id         uuid references public.products(id) on delete set null,
  ml_account_id      uuid references public.ml_accounts(id) on delete set null,
  ml_item_id         text not null,
  title              text,
  category_id        text,
  listing_type_id    text,
  price              numeric(14,2),
  currency_id        text not null default 'ARS',
  available_quantity int not null default 0,
  sold_quantity      int not null default 0,
  est_sale_fee       numeric(14,2),  -- cached fee estimate (listing_prices), in currency_id
  status             public.listing_status,
  permalink          text,
  thumbnail          text,
  has_variations     boolean not null default false,
  last_synced_at     timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (profile_id, ml_item_id)
);

-- ── Variations of a listing (size/color/etc.), stock per variation ──
create table public.listing_variations (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles(id) on delete cascade,
  ml_listing_id      uuid not null references public.ml_listings(id) on delete cascade,
  ml_variation_id    text not null,
  attributes         jsonb not null default '{}'::jsonb,
  price              numeric(14,2),
  available_quantity int not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (ml_listing_id, ml_variation_id)
);

-- ── Stock ledger (append-only). current_stock is derived from this. ─
create table public.stock_movements (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  delta      int  not null,
  reason     public.stock_reason not null,
  reference  text,    -- e.g. ml_order_id
  note       text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index stock_movements_product_idx on public.stock_movements (product_id, created_at desc);

-- ── Sales (orders coming from ML) ───────────────────────────────────
create table public.sales (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  ml_order_id   text not null,
  ml_item_id    text,
  product_id    uuid references public.products(id) on delete set null,
  quantity      int not null default 1,
  unit_price    numeric(14,2) not null default 0,
  currency_id   text not null default 'ARS',
  sale_fee      numeric(14,2) not null default 0,  -- real commission from the order
  shipping_cost numeric(14,2) not null default 0,
  net_amount    numeric(14,2),
  status        text,
  sold_at       timestamptz,
  raw           jsonb,
  created_at    timestamptz not null default now(),
  unique (profile_id, ml_order_id)  -- idempotency for webhook processing
);

-- ── Cached fee estimates from /listing_prices ───────────────────────
create table public.fee_estimates (
  id              uuid primary key default gen_random_uuid(),
  site_id         text not null default 'MLA',
  category_id     text not null,
  listing_type_id text not null,
  price           numeric(14,2) not null,
  currency_id     text not null default 'ARS',
  sale_fee_amount numeric(14,2) not null,
  details         jsonb,
  fetched_at      timestamptz not null default now(),
  unique (site_id, category_id, listing_type_id, price, currency_id)
);

-- ── Cached FX rates (USD -> ARS, by kind) ───────────────────────────
create table public.fx_rates (
  id             uuid primary key default gen_random_uuid(),
  base_currency  text not null default 'USD',
  quote_currency text not null default 'ARS',
  kind           public.fx_kind not null default 'blue',
  buy            numeric(14,4),
  sell           numeric(14,4),
  rate           numeric(14,4) not null,  -- reference rate used for calculations
  source         text,
  fetched_at     timestamptz not null default now()
);
create index fx_rates_lookup_idx
  on public.fx_rates (base_currency, quote_currency, kind, fetched_at desc);

-- ── Webhook event queue (ML notifications) — SENSITIVE: service_role ─
create table public.ml_events (
  id             uuid primary key default gen_random_uuid(),
  topic          text not null,
  resource       text not null,
  ml_user_id     bigint,
  application_id bigint,
  attempts       int not null default 0,
  status         public.ml_event_status not null default 'pending',
  payload        jsonb,
  error          text,
  received_at    timestamptz not null default now(),
  processed_at   timestamptz
);
create index ml_events_status_idx on public.ml_events (status, received_at);

-- ── Alerts (low stock, etc.) ────────────────────────────────────────
create table public.alerts (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  type        public.alert_type not null,
  product_id  uuid references public.products(id) on delete cascade,
  message     text,
  threshold   int,
  current_qty int,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index alerts_unread_idx on public.alerts (profile_id, is_read, created_at desc);
