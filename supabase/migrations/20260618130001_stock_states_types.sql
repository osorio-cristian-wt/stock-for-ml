-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ 07 · Stock states — enum types                                     ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Two-phase, per-warehouse stock model. New enum values must be added in their
-- own transaction (this file) before being used (next migrations).

-- Which quantity bucket a movement affects.
--   incoming = ordered from supplier, not yet received ("pedido")
--   on_hand  = physically in a warehouse (includes sold-not-yet-shipped)
--   reserved = confirmed sale awaiting dispatch ("por despachar")
create type public.stock_bucket as enum ('incoming', 'on_hand', 'reserved');

-- Origin governs the ML push: only user/system movements are pushed to ML.
-- ML-originated movements (sale/cancel/return) adjust the ledger only.
create type public.stock_origin as enum ('ml', 'user', 'system');

-- Fulfillment lifecycle of a sale/order line (for visibility on `sales`).
create type public.fulfillment_status as enum (
  'reserved',   -- por despachar
  'shipped',    -- despachado
  'delivered',  -- entregado
  'cancelled',  -- cancelado
  'bounced',    -- rebotado (vuelve al remitente)
  'lost'        -- perdido
);

-- Alert when a return/claim needs the user to inspect and re-stock.
alter type public.alert_type add value if not exists 'return_pending';

-- Extend stock_reason with lifecycle reasons (idempotent).
alter type public.stock_reason add value if not exists 'purchase_ordered';
alter type public.stock_reason add value if not exists 'purchase_received';
alter type public.stock_reason add value if not exists 'reserve';
alter type public.stock_reason add value if not exists 'dispatch';
alter type public.stock_reason add value if not exists 'cancellation';
alter type public.stock_reason add value if not exists 'bounce';
alter type public.stock_reason add value if not exists 'loss';
alter type public.stock_reason add value if not exists 'transfer';
