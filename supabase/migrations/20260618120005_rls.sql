-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 05 · Row Level Security                                            ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Model: every row belongs to a profile (auth.uid()). Sensitive tables have
-- RLS enabled with NO policies => clients are denied; service_role bypasses
-- RLS and is used exclusively by the Edge Functions backend.

-- ── Owner-scoped tables ─────────────────────────────────────────────
alter table public.profiles            enable row level security;
alter table public.app_settings        enable row level security;
alter table public.ml_accounts         enable row level security;
alter table public.products            enable row level security;
alter table public.ml_listings         enable row level security;
alter table public.listing_variations  enable row level security;
alter table public.stock_movements     enable row level security;
alter table public.sales               enable row level security;
alter table public.alerts              enable row level security;

create policy "profiles self access" on public.profiles
  for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "app_settings owner" on public.app_settings
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "ml_accounts owner" on public.ml_accounts
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "products owner" on public.products
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "ml_listings owner" on public.ml_listings
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "listing_variations owner" on public.listing_variations
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "stock_movements owner" on public.stock_movements
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "sales owner" on public.sales
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "alerts owner" on public.alerts
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ── Reference data: read-only for clients, written by service_role ──
alter table public.fx_rates      enable row level security;
alter table public.fee_estimates enable row level security;

create policy "fx_rates readable" on public.fx_rates
  for select to authenticated using (true);

create policy "fee_estimates readable" on public.fee_estimates
  for select to authenticated using (true);

-- ── Sensitive tables: RLS enabled, NO policies => clients denied ────
--    (service_role bypasses RLS; only Edge Functions touch these)
alter table public.ml_credentials enable row level security;
alter table public.oauth_states   enable row level security;
alter table public.ml_events      enable row level security;
