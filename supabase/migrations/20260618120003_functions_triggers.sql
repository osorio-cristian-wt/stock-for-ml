-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 03 · Functions & triggers                                          ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ── updated_at maintenance ──────────────────────────────────────────
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_updated      before update on public.profiles            for each row execute function public.tg_set_updated_at();
create trigger trg_app_settings_updated  before update on public.app_settings        for each row execute function public.tg_set_updated_at();
create trigger trg_ml_accounts_updated   before update on public.ml_accounts         for each row execute function public.tg_set_updated_at();
create trigger trg_products_updated       before update on public.products           for each row execute function public.tg_set_updated_at();
create trigger trg_ml_listings_updated    before update on public.ml_listings        for each row execute function public.tg_set_updated_at();
create trigger trg_variations_updated     before update on public.listing_variations for each row execute function public.tg_set_updated_at();

-- ── New auth user -> create profile + settings ──────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;

  insert into public.app_settings (profile_id)
  values (new.id)
  on conflict (profile_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── Stock ledger -> maintain products.current_stock ─────────────────
create or replace function public.tg_apply_stock_movement()
returns trigger
language plpgsql
as $$
begin
  update public.products
     set current_stock = current_stock + new.delta,
         updated_at    = now()
   where id = new.product_id;
  return new;
end;
$$;

create trigger trg_apply_stock_movement
  after insert on public.stock_movements
  for each row execute function public.tg_apply_stock_movement();

-- ── Low-stock / out-of-stock alerts ─────────────────────────────────
create or replace function public.tg_check_low_stock()
returns trigger
language plpgsql
as $$
declare
  thr int;
begin
  -- only act when stock actually decreased
  if new.current_stock >= old.current_stock then
    return new;
  end if;

  thr := coalesce(
    new.low_stock_threshold,
    (select low_stock_threshold from public.app_settings where profile_id = new.profile_id),
    1
  );

  if new.current_stock <= thr then
    insert into public.alerts (profile_id, type, product_id, message, threshold, current_qty)
    values (
      new.profile_id,
      case when new.current_stock <= 0 then 'out_of_stock'::public.alert_type
           else 'low_stock'::public.alert_type end,
      new.id,
      case when new.current_stock <= 0
           then 'Sin stock: ' || new.title
           else 'Stock bajo: ' || new.title || ' (' || new.current_stock || ' u.)' end,
      thr,
      new.current_stock
    );
  end if;

  return new;
end;
$$;

create trigger trg_check_low_stock
  after update of current_stock on public.products
  for each row execute function public.tg_check_low_stock();

-- ── Latest FX rate helper ───────────────────────────────────────────
create or replace function public.latest_fx_rate(
  p_base  text default 'USD',
  p_quote text default 'ARS',
  p_kind  public.fx_kind default 'blue'
)
returns numeric
language sql
stable
as $$
  select rate
    from public.fx_rates
   where base_currency = p_base
     and quote_currency = p_quote
     and kind = p_kind
   order by fetched_at desc
   limit 1;
$$;

-- ── Apply a stock movement (callable by Edge Functions / app via RPC)─
create or replace function public.apply_stock_movement(
  p_product_id uuid,
  p_delta      int,
  p_reason     public.stock_reason,
  p_reference  text default null,
  p_note       text default null
)
returns uuid
language plpgsql
security invoker
as $$
declare
  v_profile uuid;
  v_id      uuid;
begin
  select profile_id into v_profile from public.products where id = p_product_id;
  if v_profile is null then
    raise exception 'product % not found', p_product_id;
  end if;

  insert into public.stock_movements (profile_id, product_id, delta, reason, reference, note, created_by)
  values (v_profile, p_product_id, p_delta, p_reason, p_reference, p_note, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;
