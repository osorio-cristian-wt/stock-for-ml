-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 12 · Compras (purchases) + proveedores                             ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- A purchase is a draft order to a supplier (scan products by SKU, set qty).
-- Closing it posts one on_hand stock movement per line (reason=purchase,
-- origin=user → pushes the new available to ML). The per-product history is the
-- union of stock_movements + sales.

create type public.purchase_status as enum ('draft', 'closed', 'cancelled');

-- ── Suppliers (reusable) ────────────────────────────────────────────
create table public.suppliers (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  name       text not null,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index suppliers_name_uidx on public.suppliers (profile_id, lower(name));

-- ── Purchase header ─────────────────────────────────────────────────
create table public.purchases (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  supplier_id  uuid references public.suppliers(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete set null,
  status       public.purchase_status not null default 'draft',
  reference    text,            -- supplier invoice / remito number
  note         text,
  currency     text not null default 'USD',
  total        numeric(14,2) not null default 0,  -- recomputed on close
  purchased_at timestamptz,                        -- set on close
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index purchases_profile_idx on public.purchases (profile_id, created_at desc);

-- ── Purchase lines ──────────────────────────────────────────────────
create table public.purchase_items (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  quantity    int not null default 1 check (quantity > 0),
  unit_cost   numeric(14,2) not null default 0,
  currency    text not null default 'USD',
  created_at  timestamptz not null default now(),
  unique (purchase_id, product_id)
);
create index purchase_items_purchase_idx on public.purchase_items (purchase_id);

-- updated_at maintenance.
create trigger trg_suppliers_updated
  before update on public.suppliers
  for each row execute function public.tg_set_updated_at();
create trigger trg_purchases_updated
  before update on public.purchases
  for each row execute function public.tg_set_updated_at();

-- ── Close a purchase → post stock movements (idempotent) ────────────
create or replace function public.close_purchase(p_purchase_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_profile uuid;
  v_status  public.purchase_status;
  v_wh      uuid;
  v_total   numeric(14,2) := 0;
  it        record;
begin
  select profile_id, status, warehouse_id
    into v_profile, v_status, v_wh
    from public.purchases where id = p_purchase_id;
  if v_profile is null then
    raise exception 'purchase % not found', p_purchase_id;
  end if;
  if v_status <> 'draft' then
    return;  -- already closed/cancelled: idempotent no-op
  end if;

  v_wh := coalesce(v_wh, public.ensure_default_warehouse(v_profile));

  for it in
    select product_id, quantity, unit_cost
      from public.purchase_items where purchase_id = p_purchase_id
  loop
    insert into public.stock_movements
      (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note, created_by)
    values
      (v_profile, it.product_id, v_wh, 'on_hand', it.quantity, 'purchase', 'user',
       p_purchase_id::text, 'Compra ' || left(p_purchase_id::text, 8), (select auth.uid()));
    v_total := v_total + (it.quantity * coalesce(it.unit_cost, 0));
  end loop;

  update public.purchases
     set status = 'closed',
         purchased_at = coalesce(purchased_at, now()),
         total = v_total,
         updated_at = now()
   where id = p_purchase_id;
end;
$$;

-- ── Add a line to an open purchase (sums qty when the SKU repeats) ──
create or replace function public.add_purchase_item(
  p_purchase_id uuid,
  p_product_id  uuid,
  p_qty         int,
  p_unit_cost   numeric default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_profile uuid;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'quantity must be positive';
  end if;
  select profile_id into v_profile
    from public.purchases where id = p_purchase_id and status = 'draft';
  if v_profile is null then
    raise exception 'open purchase % not found', p_purchase_id;
  end if;

  insert into public.purchase_items
    (profile_id, purchase_id, product_id, quantity, unit_cost)
  values
    (v_profile, p_purchase_id, p_product_id, p_qty, coalesce(p_unit_cost, 0))
  on conflict (purchase_id, product_id) do update set
    quantity  = purchase_items.quantity + excluded.quantity,
    unit_cost = case when p_unit_cost is not null
                     then excluded.unit_cost else purchase_items.unit_cost end;
end;
$$;

-- ── RLS: owner-scoped ───────────────────────────────────────────────
alter table public.suppliers      enable row level security;
alter table public.purchases      enable row level security;
alter table public.purchase_items enable row level security;

create policy "suppliers owner" on public.suppliers
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "purchases owner" on public.purchases
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy "purchase_items owner" on public.purchase_items
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ── Realtime: app streams suppliers/purchases/items ─────────────────
do $$
declare
  t text;
  tables text[] := array['suppliers', 'purchases', 'purchase_items'];
begin
  foreach t in array tables loop
    execute format('alter table public.%I replica identity full', t);
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
