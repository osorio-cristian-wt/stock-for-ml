-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 24 · RF-37 — Estado completo de la publicación                      ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- ML define 7 estados; el import solo mapeaba 4 y descartaba sub_status
-- (out_of_stock / paused_by_seller / deleted / …), así que la app no podía
-- distinguir "pausada por vos" de "pausada sin stock". Los valores nuevos
-- del enum no se usan en esta migración (solo en runtime desde las Edge
-- Functions), así que pueden convivir con el alter table en el mismo archivo.

alter type public.listing_status add value if not exists 'not_yet_active';
alter type public.listing_status add value if not exists 'payment_required';

alter table public.ml_listings
  add column sub_status text[] not null default '{}';
comment on column public.ml_listings.sub_status is
  'sub_status de ML (out_of_stock, paused_by_seller, deleted, …). RF-37.';
