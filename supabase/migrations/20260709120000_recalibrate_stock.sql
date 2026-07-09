-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 28 · RF-49 — Recalibrar stock (zona peligrosa)                     ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Red de seguridad manual contra el drift del stock (p. ej. los negativos
-- que dejó el doble descuento de órdenes pre-import antes del cutoff):
--   · producto PUBLICADO  → stock vendible = available de su publicación ML
--     (max() entre publicaciones no-Full activas/pausadas: el push replica el
--     mismo número en todas, así que el máximo es el valor menos degradado);
--   · producto INTERNO    → stock vendible = 0 (para recontar de cero).
-- El ajuste va en UN movimiento al depósito principal con origin='ml':
-- NUNCA pushea nada a ML (el número ya es el de ML, o el producto no está
-- publicado). Los depósitos no vendibles y el espejo Full quedan intactos.

create or replace function public.recalibrate_stock_for(p_profile uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_default  uuid := public.ensure_default_warehouse(p_profile);
  rec        record;
  v_adjusted int  := 0;
begin
  for rec in
    select p.id as product_id,
           coalesce((
             select max(l.available_quantity)
               from public.ml_listings l
              where l.product_id = p.id
                and l.status in ('active', 'paused')
                and coalesce(l.logistic_type, '') <> 'fulfillment'
           ), 0) as target,
           coalesce((
             select sum(ps.on_hand)
               from public.product_stock ps
               join public.warehouses w on w.id = ps.warehouse_id
              where ps.product_id = p.id
                and w.is_sellable
                and not w.ml_fulfillment
           ), 0) as current_qty
      from public.products p
     where p.profile_id = p_profile
  loop
    if rec.target <> rec.current_qty then
      insert into public.stock_movements
        (profile_id, product_id, warehouse_id, bucket, delta,
         reason, origin, reference, note)
      values
        (p_profile, rec.product_id, v_default, 'on_hand',
         rec.target - rec.current_qty, 'adjustment', 'ml',
         'recalibration', 'Recalibración: stock vendible = ML (0 si es interno)');
      v_adjusted := v_adjusted + 1;
    end if;
  end loop;

  return v_adjusted;
end;
$$;

comment on function public.recalibrate_stock_for(uuid) is
  'RF-49: recalibra el stock vendible de TODOS los productos de un perfil '
  '(publicados = available ML, internos = 0). Solo servidor/tests.';

-- La variante por-perfil no es invocable por clientes (evita recalibrar
-- perfiles ajenos); la app usa el wrapper scoped a auth.uid().
revoke execute on function public.recalibrate_stock_for(uuid)
  from public, anon, authenticated;

create or replace function public.recalibrate_stock()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'solo usuarios autenticados';
  end if;
  return public.recalibrate_stock_for(auth.uid());
end;
$$;

comment on function public.recalibrate_stock() is
  'RF-49: zona peligrosa de Ajustes — recalibra el stock del propio perfil.';
