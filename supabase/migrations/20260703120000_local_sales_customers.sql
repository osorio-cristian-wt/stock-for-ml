-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 16 · Ventas locales (fuera de ML) + clientes + datos de proveedor  ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- El backend diferencia el canal de cada venta: 'ml' (orden importada por
-- webhook/sync) o 'local' (venta directa registrada en la app). La venta
-- local puede atribuirse a un cliente del padrón propio (customers, RLS por
-- profile_id) o quedar sin cliente. Los proveedores ganan datos fiscales
-- opcionales (razón social, CUIT/CUIL, contacto).

-- ── Canal de venta ───────────────────────────────────────────────────
create type public.sale_channel as enum ('ml', 'local');

-- ── Clientes (padrón propio del usuario) ─────────────────────────────
create table public.customers (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  name       text not null,
  legal_name text,
  tax_id     text,   -- CUIT / CUIL / DNI
  phone      text,
  email      text,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index customers_profile_name_idx
  on public.customers (profile_id, lower(name));
create trigger trg_customers_updated
  before update on public.customers
  for each row execute function public.tg_set_updated_at();

alter table public.customers enable row level security;
create policy "customers owner" on public.customers
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ── Proveedores: datos fiscales/contacto opcionales ──────────────────
alter table public.suppliers
  add column if not exists legal_name text,
  add column if not exists tax_id     text,
  add column if not exists phone      text,
  add column if not exists email      text;

-- ── Ventas: canal + cliente + nota; ml_order_id solo aplica a ML ─────
alter table public.sales
  add column channel     public.sale_channel not null default 'ml',
  add column customer_id uuid references public.customers(id) on delete set null,
  add column note        text;
alter table public.sales alter column ml_order_id drop not null;
alter table public.sales add constraint sales_ml_order_required
  check (channel <> 'ml' or ml_order_id is not null);

-- ── RPC: registrar una venta local ───────────────────────────────────
-- Crea la venta (channel='local') y descuenta on_hand del depósito elegido
-- (o el principal). El movimiento va con origin='user', así el trigger
-- encola el push del nuevo disponible a ML (no se sobrevende allá).
create or replace function public.create_local_sale(
  p_product_id   uuid,
  p_quantity     int,
  p_unit_price   numeric,
  p_customer_id  uuid default null,
  p_warehouse_id uuid default null,
  p_note         text default null
)
returns uuid
language plpgsql
security invoker
as $$
declare
  v_profile uuid;
  v_sale    uuid;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'quantity must be > 0';
  end if;

  select profile_id into v_profile from public.products where id = p_product_id;
  if v_profile is null then
    raise exception 'product % not found', p_product_id;
  end if;

  insert into public.sales
    (profile_id, channel, customer_id, product_id, quantity, unit_price,
     currency_id, sale_fee, shipping_cost, net_amount, status,
     fulfillment_status, sold_at, note)
  values
    (v_profile, 'local', p_customer_id, p_product_id, p_quantity,
     coalesce(p_unit_price, 0), 'ARS', 0, 0,
     coalesce(p_unit_price, 0) * p_quantity, 'paid',
     'delivered', now(), p_note)
  returning id into v_sale;

  perform public.apply_stock_movement(
    p_product_id, -p_quantity, 'sale', v_sale::text,
    coalesce(p_note, 'Venta local'), p_warehouse_id, 'on_hand', 'user');

  return v_sale;
end;
$$;

-- ── Realtime ─────────────────────────────────────────────────────────
do $$
begin
  alter table public.customers replica identity full;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'customers'
  ) then
    alter publication supabase_realtime add table public.customers;
  end if;
end $$;
