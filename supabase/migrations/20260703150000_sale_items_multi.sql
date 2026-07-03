-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 17 · Ventas multi-ítem (sale_items) + venta local transaccional    ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Una venta (de ML o local) puede tener VARIOS productos. Hasta ahora `sales`
-- aplastaba la orden a un solo ml_item_id/product_id; se agrega `sale_items`
-- (una línea por producto, como purchase_items) y `sales.total_amount` para
-- el importe real de la orden completa.
--
-- Además `create_local_sale` pasa a ser multi-ítem, TRANSACCIONAL e
-- IDEMPOTENTE: valida ANTES de escribir que cada línea tenga disponible
-- suficiente en el depósito elegido (si no, error y no queda nada a medias —
-- arregla el caso "se registró la venta pero el stock total no cambió" al
-- vender desde un depósito sin stock o no vendible), y acepta un id de venta
-- generado por el cliente para que un reintento no duplique.

-- ── Líneas de venta ──────────────────────────────────────────────────
create table public.sale_items (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  sale_id    uuid not null references public.sales(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  ml_item_id text,
  title      text,  -- snapshot para mostrar aunque el producto se borre
  quantity   int not null check (quantity > 0),
  unit_price numeric(14,2) not null default 0,
  sale_fee   numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);
create index sale_items_sale_idx on public.sale_items (sale_id);
-- El historial por producto busca sus líneas de venta directamente.
create index sale_items_product_idx on public.sale_items (product_id);

alter table public.sale_items enable row level security;
create policy "sale_items owner" on public.sale_items
  for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- ── Importe total real de la venta (Σ líneas / total de la orden ML) ─
alter table public.sales add column total_amount numeric(14,2);

-- ── create_local_sale v2 (multi-ítem) ────────────────────────────────
drop function if exists public.create_local_sale(uuid, int, numeric, uuid, uuid, text);

create or replace function public.create_local_sale(
  p_items        jsonb,                -- [{product_id, quantity, unit_price}]
  p_customer_id  uuid default null,
  p_warehouse_id uuid default null,
  p_note         text default null,
  p_sale_id      uuid default null     -- id del cliente para idempotencia
)
returns uuid
language plpgsql
security invoker
as $$
declare
  v_profile uuid;
  v_sale    uuid;
  v_wh      uuid;
  it        record;
  v_avail   int;
  v_total   numeric := 0;
  v_qty     int := 0;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'la venta necesita al menos un ítem';
  end if;

  -- Idempotencia: si el cliente reintenta con el mismo id, no-op.
  if p_sale_id is not null then
    select id into v_sale from public.sales where id = p_sale_id;
    if found then
      return v_sale;
    end if;
  end if;

  select profile_id into v_profile from public.products
   where id = ((p_items->0)->>'product_id')::uuid;
  if v_profile is null then
    raise exception 'producto no encontrado';
  end if;

  v_wh := coalesce(p_warehouse_id, public.ensure_default_warehouse(v_profile));

  -- Validación ANTES de escribir: cada línea debe estar cubierta por el
  -- disponible (on_hand − reserved) del depósito elegido. Si algo no
  -- alcanza, se aborta todo (función = una transacción, nada a medias).
  for it in
    select (e->>'product_id')::uuid            as pid,
           coalesce((e->>'quantity')::int, 0)  as qty
      from jsonb_array_elements(p_items) e
  loop
    if it.qty <= 0 then
      raise exception 'cantidad inválida (%) para el producto %', it.qty, it.pid;
    end if;
    if not exists (select 1 from public.products
                    where id = it.pid and profile_id = v_profile) then
      raise exception 'producto % no encontrado', it.pid;
    end if;
    select coalesce(on_hand - reserved, 0) into v_avail
      from public.product_stock
     where product_id = it.pid and warehouse_id = v_wh;
    if coalesce(v_avail, 0) < it.qty then
      raise exception
        'stock insuficiente en el depósito: producto %, disponible %, pedido %',
        it.pid, coalesce(v_avail, 0), it.qty;
    end if;
  end loop;

  insert into public.sales
    (id, profile_id, channel, customer_id, quantity, unit_price, currency_id,
     sale_fee, shipping_cost, net_amount, total_amount, status,
     fulfillment_status, sold_at, note)
  values
    (coalesce(p_sale_id, gen_random_uuid()), v_profile, 'local', p_customer_id,
     0, 0, 'ARS', 0, 0, 0, 0, 'paid', 'delivered', now(), p_note)
  returning id into v_sale;

  for it in
    select (e->>'product_id')::uuid                as pid,
           (e->>'quantity')::int                   as qty,
           coalesce((e->>'unit_price')::numeric, 0) as price
      from jsonb_array_elements(p_items) e
  loop
    insert into public.sale_items
      (profile_id, sale_id, product_id, title, quantity, unit_price)
    select v_profile, v_sale, it.pid, p.title, it.qty, it.price
      from public.products p where p.id = it.pid;

    perform public.apply_stock_movement(
      it.pid, -it.qty, 'sale', v_sale::text,
      coalesce(p_note, 'Venta local'), v_wh, 'on_hand', 'user');

    v_total := v_total + (it.qty * it.price);
    v_qty   := v_qty + it.qty;
  end loop;

  update public.sales
     set quantity     = v_qty,
         unit_price   = case when v_qty > 0 then round(v_total / v_qty, 2) else 0 end,
         net_amount   = v_total,
         total_amount = v_total,
         -- una venta de un solo producto conserva el acceso directo
         product_id   = case when jsonb_array_length(p_items) = 1
                             then ((p_items->0)->>'product_id')::uuid end
   where id = v_sale;

  return v_sale;
end;
$$;
