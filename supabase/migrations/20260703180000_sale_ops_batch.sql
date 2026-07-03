-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 18 · Lote operativo: precio de venta, venta multi-depósito,        ║
-- ║      despacho ML multi-depósito, visibilidad del push a ML         ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Pedidos del dueño (2026-07-03):
--  · precio de venta propio en products (obligatorio en el alta desde la app;
--    sugiere el precio en ventas locales de productos sin publicación ML)
--  · una venta local puede sacar stock de VARIOS depósitos (depósito por línea)
--  · las ventas de ML pueden despacharse desde varios depósitos vendibles
--    (antes todo caía en el principal aunque no tuviera stock)
--  · la app puede VER la cola de push a ML (para avisar "no se subió") y
--    reintentar las filas en error

-- ── Precio de venta propio ───────────────────────────────────────────
alter table public.products
  add column sale_price numeric(14,2) check (sale_price is null or sale_price >= 0);
comment on column public.products.sale_price is
  'Precio de venta local (ARS). Para publicados en ML manda el precio de la publicación.';

-- ── create_local_sale v3: depósito por línea ─────────────────────────
-- p_items ahora acepta warehouse_id opcional por línea; sin él, la línea usa
-- el depósito de la cabecera (p_warehouse_id) o el principal. La validación
-- agrupa por (producto, depósito) para que dos líneas del mismo producto no
-- pasen por separado lo que juntas no cubren.
create or replace function public.create_local_sale(
  p_items        jsonb,                -- [{product_id, quantity, unit_price, warehouse_id?}]
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

  -- Validación ANTES de escribir, agrupada por (producto, depósito): cada
  -- grupo debe estar cubierto por el disponible (on_hand − reserved) de SU
  -- depósito. Si algo no alcanza, se aborta todo (nada a medias).
  for it in
    select (e->>'product_id')::uuid                          as pid,
           coalesce((e->>'warehouse_id')::uuid, v_wh)        as wh,
           sum(coalesce((e->>'quantity')::int, 0))           as qty,
           bool_or(coalesce((e->>'quantity')::int, 0) <= 0)  as bad_qty
      from jsonb_array_elements(p_items) e
     group by 1, 2
  loop
    if it.bad_qty then
      raise exception 'cantidad inválida para el producto %', it.pid;
    end if;
    if not exists (select 1 from public.products
                    where id = it.pid and profile_id = v_profile) then
      raise exception 'producto % no encontrado', it.pid;
    end if;
    select coalesce(on_hand - reserved, 0) into v_avail
      from public.product_stock
     where product_id = it.pid and warehouse_id = it.wh;
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
    select (e->>'product_id')::uuid                   as pid,
           coalesce((e->>'warehouse_id')::uuid, v_wh) as wh,
           (e->>'quantity')::int                      as qty,
           coalesce((e->>'unit_price')::numeric, 0)   as price
      from jsonb_array_elements(p_items) e
  loop
    insert into public.sale_items
      (profile_id, sale_id, product_id, title, quantity, unit_price)
    select v_profile, v_sale, it.pid, p.title, it.qty, it.price
      from public.products p where p.id = it.pid;

    perform public.apply_stock_movement(
      it.pid, -it.qty, 'sale', v_sale::text,
      coalesce(p_note, 'Venta local'), it.wh, 'on_hand', 'user');

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

-- ── reconcile_order_stock v2: despacho desde VARIOS depósitos ────────
-- Antes toda reserva/despacho de una orden ML caía en el depósito por defecto
-- aunque no tuviera stock. Ahora cada delta se reparte entre los depósitos
-- VENDIBLES con disponible (el principal primero); las liberaciones y
-- devoluciones vuelven a los depósitos donde la orden había reservado o
-- despachado. Si aun así falta stock, el resto cae en el principal (igual que
-- antes: el faltante queda visible como negativo, nunca se pierde la venta).
create or replace function public.reconcile_order_stock(
  p_profile_id   uuid,
  p_order_id     text,
  p_warehouse_id uuid,
  p_targets      jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_default uuid := coalesce(p_warehouse_id, public.ensure_default_warehouse(p_profile_id));
  t         jsonb;
  v_pid     uuid;
  v_bucket  public.stock_bucket;
  v_desired int;
  v_current int;
  v_delta   int;
  v_remaining int;
  v_take    int;
  alloc     record;
  v_reason  public.stock_reason;
begin
  -- One worker per order: serialize concurrent process-events / sync-orders.
  perform pg_advisory_xact_lock(hashtextextended(p_order_id, 0));

  for t in select * from jsonb_array_elements(p_targets) loop
    v_pid := (t->>'product_id')::uuid;
    foreach v_bucket in array array['reserved', 'on_hand']::public.stock_bucket[] loop
      v_desired := coalesce((t->>(v_bucket::text))::int, 0);
      select coalesce(sum(delta), 0) into v_current
        from public.stock_movements
       where reference = p_order_id and product_id = v_pid and bucket = v_bucket;
      v_delta := v_desired - v_current;
      if v_delta = 0 then
        continue;
      end if;

      v_reason := case
        when v_bucket = 'reserved' and v_delta > 0 then 'reserve'
        when v_bucket = 'reserved' and v_delta < 0 then 'cancellation'
        when v_bucket = 'on_hand'  and v_delta < 0 then 'dispatch'
        else 'return'
      end::public.stock_reason;

      v_remaining := abs(v_delta);

      if v_delta < 0 and v_bucket = 'on_hand' then
        -- Despacho: primero donde la orden tiene (o tuvo) reserva, después
        -- los depósitos vendibles con disponible (principal primero).
        for alloc in
          select wh, cap from (
            select m.warehouse_id as wh, sum(m.delta) as cap, 0 as pri
              from public.stock_movements m
             where m.reference = p_order_id and m.product_id = v_pid
               and m.bucket = 'reserved' and m.delta > 0
             group by m.warehouse_id
            union all
            select ps.warehouse_id, greatest(ps.on_hand - ps.reserved, 0), 1
              from public.product_stock ps
              join public.warehouses w on w.id = ps.warehouse_id
             where ps.product_id = v_pid and w.is_sellable
               and ps.on_hand - ps.reserved > 0
          ) c
          join public.warehouses w2 on w2.id = c.wh
          order by c.pri, (not w2.is_default), c.cap desc
        loop
          exit when v_remaining <= 0;
          v_take := least(v_remaining, alloc.cap::int);
          if v_take <= 0 then continue; end if;
          insert into public.stock_movements
            (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
          values (p_profile_id, v_pid, alloc.wh, v_bucket, -v_take, v_reason,
                  'ml', p_order_id, 'reconcile ' || p_order_id);
          v_remaining := v_remaining - v_take;
        end loop;

      elsif v_delta > 0 and v_bucket = 'reserved' then
        -- Reservar: repartir entre depósitos vendibles con disponible.
        for alloc in
          select ps.warehouse_id as wh,
                 greatest(ps.on_hand - ps.reserved, 0) as cap
            from public.product_stock ps
            join public.warehouses w on w.id = ps.warehouse_id
           where ps.product_id = v_pid and w.is_sellable
             and ps.on_hand - ps.reserved > 0
           order by (not w.is_default), cap desc
        loop
          exit when v_remaining <= 0;
          v_take := least(v_remaining, alloc.cap::int);
          if v_take <= 0 then continue; end if;
          insert into public.stock_movements
            (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
          values (p_profile_id, v_pid, alloc.wh, v_bucket, v_take, v_reason,
                  'ml', p_order_id, 'reconcile ' || p_order_id);
          v_remaining := v_remaining - v_take;
        end loop;

      elsif v_delta < 0 and v_bucket = 'reserved' then
        -- Liberar reserva: en los depósitos donde la orden la mantiene.
        for alloc in
          select m.warehouse_id as wh, sum(m.delta) as cap
            from public.stock_movements m
           where m.reference = p_order_id and m.product_id = v_pid
             and m.bucket = 'reserved'
           group by m.warehouse_id
          having sum(m.delta) > 0
           order by cap desc
        loop
          exit when v_remaining <= 0;
          v_take := least(v_remaining, alloc.cap::int);
          if v_take <= 0 then continue; end if;
          insert into public.stock_movements
            (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
          values (p_profile_id, v_pid, alloc.wh, v_bucket, -v_take, v_reason,
                  'ml', p_order_id, 'reconcile ' || p_order_id);
          v_remaining := v_remaining - v_take;
        end loop;

      else
        -- Devolución de físico: a los depósitos desde donde se despachó.
        for alloc in
          select m.warehouse_id as wh, -sum(m.delta) as cap
            from public.stock_movements m
           where m.reference = p_order_id and m.product_id = v_pid
             and m.bucket = 'on_hand'
           group by m.warehouse_id
          having sum(m.delta) < 0
           order by cap desc
        loop
          exit when v_remaining <= 0;
          v_take := least(v_remaining, alloc.cap::int);
          if v_take <= 0 then continue; end if;
          insert into public.stock_movements
            (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
          values (p_profile_id, v_pid, alloc.wh, v_bucket, v_take, v_reason,
                  'ml', p_order_id, 'reconcile ' || p_order_id);
          v_remaining := v_remaining - v_take;
        end loop;
      end if;

      -- Resto sin cobertura → depósito principal (comportamiento previo).
      if v_remaining > 0 then
        insert into public.stock_movements
          (profile_id, product_id, warehouse_id, bucket, delta, reason, origin, reference, note)
        values (p_profile_id, v_pid, v_default, v_bucket,
                sign(v_delta) * v_remaining, v_reason,
                'ml', p_order_id, 'reconcile ' || p_order_id);
      end if;
    end loop;
  end loop;
end;
$$;

-- ── Cola de push a ML visible para el dueño ──────────────────────────
-- La app muestra "quedaron N productos sin subir a ML" en vez de fallar en
-- silencio. Solo lectura; escribir sigue siendo del service role.
create policy "push queue readable by owner" on public.stock_push_queue
  for select to authenticated
  using (exists (
    select 1 from public.products p
     where p.id = stock_push_queue.product_id
       and p.profile_id = (select auth.uid())
  ));

-- Reintento manual desde la app: re-encola las filas en error del usuario.
create or replace function public.retry_stock_push()
returns int
language sql
security definer
set search_path = public
as $$
  with mine as (
    update public.stock_push_queue q
       set status = 'pending', attempts = 0,
           enqueued_at = now(), processed_at = null, error = null
     where q.status = 'error'
       and exists (select 1 from public.products p
                    where p.id = q.product_id
                      and p.profile_id = (select auth.uid()))
    returning 1
  )
  select count(*)::int from mine;
$$;

revoke all on function public.retry_stock_push() from public, anon;
grant execute on function public.retry_stock_push() to authenticated;

-- ── Alertas de stock bajo: detectar SIEMPRE, no solo al descontar ────
-- El trigger original solo corría en updates de current_stock y solo si el
-- stock BAJABA: un producto creado ya bajo el umbral (o cargado con 2 u. y
-- umbral 5, o al que se le sube el umbral) nunca alertaba. Ahora:
--  · corre en INSERT y en updates de current_stock O low_stock_threshold;
--  · alerta si quedó en/bajo el umbral, sin duplicar (dedup por alerta sin
--    leer del mismo tipo);
--  · si el stock vuelve a superar el umbral, las alertas sin leer se marcan
--    leídas solas (dejan de hacer ruido).
create or replace function public.tg_check_low_stock()
returns trigger
language plpgsql
as $$
declare
  thr int;
  v_type public.alert_type;
begin
  thr := coalesce(
    new.low_stock_threshold,
    (select low_stock_threshold from public.app_settings where profile_id = new.profile_id),
    1
  );

  if new.current_stock <= thr then
    v_type := case when new.current_stock <= 0
                   then 'out_of_stock'::public.alert_type
                   else 'low_stock'::public.alert_type end;
    if not exists (
      select 1 from public.alerts
       where product_id = new.id and type = v_type and is_read = false
    ) then
      insert into public.alerts (profile_id, type, product_id, message, threshold, current_qty)
      values (
        new.profile_id,
        v_type,
        new.id,
        case when new.current_stock <= 0
             then 'Sin stock: ' || new.title
             else 'Stock bajo: ' || new.title || ' (' || new.current_stock || ' u.)' end,
        thr,
        new.current_stock
      );
    end if;
  else
    -- Se recuperó: silenciar las alertas pendientes de este producto.
    update public.alerts
       set is_read = true
     where product_id = new.id
       and type in ('low_stock', 'out_of_stock')
       and is_read = false;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_check_low_stock on public.products;
create trigger trg_check_low_stock
  after insert or update of current_stock, low_stock_threshold on public.products
  for each row execute function public.tg_check_low_stock();

-- ── Tokens ML: refresco horario ──────────────────────────────────────
-- El token de ML dura 6 h y el job corría cada 5 h refrescando lo que vencía
-- dentro de 1 h: un token emitido justo después de una corrida podía vencer
-- antes de la siguiente (las Edge Functions igual refrescan on-demand, pero el
-- cron es la red de seguridad). Pasa a correr CADA HORA.
create or replace function private.register_ml_cron_jobs()
returns void
language plpgsql
security definer
set search_path = private, public, extensions
as $$
declare
  v_base text;
  v_key  text;
begin
  select value into v_base from private.app_config where key = 'functions_base_url';
  select value into v_key  from private.app_config where key = 'service_role_key';

  if v_base is null or v_key is null then
    raise exception 'Configure functions_base_url and service_role_key in private.app_config first';
  end if;

  perform cron.unschedule(jobname) from cron.job
    where jobname in ('ml-refresh-tokens', 'ml-fx-rates', 'ml-process-events',
                      'ml-sync-orders', 'ml-push-stock');

  -- Refresh ML access tokens hourly (token TTL is 6h; threshold 75 min).
  perform cron.schedule('ml-refresh-tokens', '0 * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/refresh-tokens', v_key));

  -- Refresh FX (dollar) rate every 30 minutes.
  perform cron.schedule('ml-fx-rates', '*/30 * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/fx-rates', v_key));

  -- Drain the webhook event queue every minute.
  perform cron.schedule('ml-process-events', '* * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/process-events', v_key));

  -- Safety-net pull of recent orders every 15 minutes (in case a webhook is missed).
  perform cron.schedule('ml-sync-orders', '*/15 * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/sync-orders', v_key));

  -- Push user/system stock changes to ML every minute (anti-loop: ML events excluded).
  perform cron.schedule('ml-push-stock', '* * * * *', format($cmd$
    select net.http_post(
      url     := %L,
      headers := jsonb_build_object('Authorization', 'Bearer ' || %L, 'Content-Type', 'application/json'),
      body    := '{}'::jsonb
    );
  $cmd$, v_base || '/push-stock', v_key));
end;
$$;

revoke all on function private.register_ml_cron_jobs() from public, anon, authenticated;
