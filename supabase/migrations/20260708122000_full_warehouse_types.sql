-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 22 · RF-38 — Full (ML): tipos                                       ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- En archivo propio: un valor de enum nuevo no puede usarse en la misma
-- transacción que lo crea (mismo patrón que 20260618130001).

-- Espejo del stock en Full (origin=ml, no re-empuja a ML).
alter type public.stock_reason add value if not exists 'full_sync';
-- Descuento local al atribuir mercadería detectada en Full a un depósito.
alter type public.stock_reason add value if not exists 'full_inbound';
