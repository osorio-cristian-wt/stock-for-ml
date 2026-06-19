-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 10 · Stock states — RLS                                            ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ── Owner-scoped tables ─────────────────────────────────────────────
alter table public.warehouses         enable row level security;
alter table public.product_categories enable row level security;
alter table public.product_stock      enable row level security;

create policy "warehouses owner" on public.warehouses
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "product_categories owner" on public.product_categories
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- product_stock is maintained by the (security definer) ledger trigger.
-- Clients read only; never write directly.
create policy "product_stock readable" on public.product_stock
  for select to authenticated
  using (profile_id = (select auth.uid()));

-- ── Sensitive: RLS enabled, NO policies => clients denied ───────────
alter table public.stock_push_queue enable row level security;
