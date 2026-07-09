-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 27 · RF-45 — Desconectar ML y borrar todos los datos                ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Decisión 2026-07-08: desconectar CONSERVA el histórico (productos, ventas y
-- espejos quedan; solo se revocan credenciales y la cuenta deja de sincronizar).
-- "Borrar todo" es una acción aparte, transaccional y limitada al propio
-- profile_id (security definer para alcanzar ml_accounts/ml_credentials, que
-- no tienen policies de cliente).

create or replace function public.disconnect_ml()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'solo usuarios autenticados';
  end if;
  -- ml_credentials cae en cascada; listings/ventas quedan como histórico.
  delete from public.ml_accounts where profile_id = auth.uid();
  delete from public.oauth_states where profile_id = auth.uid();
end;
$$;

create or replace function public.wipe_profile_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'solo usuarios autenticados';
  end if;

  -- Orden respetando FKs (hijos primero). Todo scoped al propio perfil.
  delete from public.sale_charges       where profile_id = v_uid;
  delete from public.sale_items         where profile_id = v_uid;
  delete from public.sales              where profile_id = v_uid;
  delete from public.full_inbounds      where profile_id = v_uid;
  delete from public.stock_push_queue
   where product_id in (select id from public.products where profile_id = v_uid);
  delete from public.stock_movements    where profile_id = v_uid;
  delete from public.product_stock      where profile_id = v_uid;
  delete from public.listing_variations where profile_id = v_uid;
  delete from public.ml_listings        where profile_id = v_uid;
  delete from public.import_jobs        where profile_id = v_uid;
  delete from public.purchase_items
   where purchase_id in (select id from public.purchases where profile_id = v_uid);
  delete from public.purchases          where profile_id = v_uid;
  delete from public.customers          where profile_id = v_uid;
  delete from public.suppliers          where profile_id = v_uid;
  delete from public.alerts             where profile_id = v_uid;
  delete from public.products           where profile_id = v_uid;
  delete from public.warehouses         where profile_id = v_uid;
  delete from public.product_categories where profile_id = v_uid;
  delete from public.ml_accounts        where profile_id = v_uid;  -- credentials cascade
  delete from public.oauth_states       where profile_id = v_uid;
  delete from public.app_settings       where profile_id = v_uid;
end;
$$;

revoke all on function public.disconnect_ml() from public, anon;
revoke all on function public.wipe_profile_data() from public, anon;
grant execute on function public.disconnect_ml() to authenticated;
grant execute on function public.wipe_profile_data() to authenticated;
