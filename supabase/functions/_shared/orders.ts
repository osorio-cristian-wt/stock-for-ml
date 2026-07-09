// Shared order/shipment reconciliation used by process-events and sync-orders.
//
// Anti-loop principle: ML events (sale / cancellation / return) adjust the
// internal ledger ONLY — they never push back to ML (ML already reflects the
// sale on its side). The push to ML happens exclusively for user/system-origin
// movements, drained by the push-stock function.
//
// Reconciliation, not deltas: we compute the *cumulative effect the order must
// have given its current status* (read fresh) and let reconcile_order_stock
// insert whatever compensating movement reaches that state. This is idempotent
// and order-independent (a stale "paid" after a "cancelled" re-reads cancelled).
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MeliClient, MeliOrder, MeliShipment, MeliShipmentCosts } from "./meli.ts";

export interface MlAccountRow {
  id: string;
  profile_id: string;
  ml_user_id: number;
}

/** One typed seller-borne charge of a sale (row of sale_charges). RF-39. */
export interface ChargeRow {
  kind: "commission" | "shipping" | "tax" | "discount" | "financing" | "other";
  amount: number;
  currency_id: string;
  source: "order" | "shipment" | "payment" | "billing";
  raw?: Record<string, unknown>;
}

/** Extracts the seller-borne charges of an order (pure, for tests). RF-39.
 * - commission: order_items[].sale_fee is PER UNIT (ML docs) => × quantity.
 * - shipping:   what the seller pays for the shipment (senders[].cost).
 * - tax:        order-level taxes total. */
export function chargeRows(
  order: MeliOrder,
  shipCosts: MeliShipmentCosts | null,
): ChargeRow[] {
  const currency = order.currency_id ?? "ARS";
  const rows: ChargeRow[] = [];

  const commission = (order.order_items ?? []).reduce(
    (s, i) => s + (i.sale_fee ?? 0) * Math.abs(i.quantity ?? 1),
    0,
  );
  if (commission > 0) {
    rows.push({ kind: "commission", amount: commission, currency_id: currency, source: "order" });
  }

  const sellerId = order.seller?.id;
  const shipping = (shipCosts?.senders ?? [])
    .filter((s) => sellerId == null || s.user_id == null || s.user_id === sellerId)
    .reduce((s, x) => s + (x.cost ?? 0), 0);
  if (shipping > 0) {
    rows.push({
      kind: "shipping",
      amount: shipping,
      currency_id: currency,
      source: "shipment",
      raw: { gross_amount: shipCosts?.gross_amount ?? null },
    });
  }

  const tax = order.taxes?.amount ?? 0;
  if (tax > 0) {
    rows.push({
      kind: "tax",
      amount: tax,
      currency_id: order.taxes?.currency_id ?? currency,
      source: "order",
    });
  }

  return rows;
}

/** True when the order predates the listing mirror (pure, for tests).
 *
 * The initial import seeds stock from ML's CURRENT available_quantity, which
 * already has every past sale discounted on ML's side. Reconciling one of
 * those historical orders would discount the sale a second time (the "-9
 * stock" bug). Pre-tracking orders are still recorded as sales (history,
 * stats, charges) but their stock effect is pinned to zero — and because
 * reconcile_order_stock compensates toward the desired state, re-running
 * sync-orders REPAIRS any double discount already applied. */
export function preTracking(
  orderDate: string | null | undefined,
  listingCreatedAt: string | null | undefined,
): boolean {
  if (!orderDate || !listingCreatedAt) return false;
  const order = new Date(orderDate).getTime();
  const mirrored = new Date(listingCreatedAt).getTime();
  if (Number.isNaN(order) || Number.isNaN(mirrored)) return false;
  return order < mirrored;
}

type Fulfillment = "reserved" | "shipped" | "delivered" | "cancelled" | "bounced" | "lost";
interface Effect { reserved: number; on_hand: number; fulfillment: Fulfillment }

/** Desired cumulative (reserved, on_hand) effect of an order, given its state. */
function effectFor(orderStatus: string, shipStatus: string | undefined, qty: number): Effect {
  if (orderStatus === "cancelled" || orderStatus === "invalid") {
    return { reserved: 0, on_hand: 0, fulfillment: "cancelled" };
  }
  switch (shipStatus) {
    case "shipped":
      return { reserved: 0, on_hand: -qty, fulfillment: "shipped" };
    case "delivered":
      return { reserved: 0, on_hand: -qty, fulfillment: "delivered" };
    case "not_delivered":
    case "returning_to_sender":
    case "returned":
      // Sold + shipped; the unit physically returns via a user-confirmed restock.
      return { reserved: 0, on_hand: -qty, fulfillment: "bounced" };
    default:
      // No shipment yet / pending / ready_to_ship / handling => held as reserved.
      return { reserved: qty, on_hand: 0, fulfillment: "reserved" };
  }
}

/** Reconcile an order's stock from order + (optional) shipment state. */
async function reconcileOrder(
  admin: SupabaseClient,
  account: MlAccountRow,
  order: MeliOrder,
  shipment: MeliShipment | null,
  shipCosts: MeliShipmentCosts | null = null,
): Promise<void> {
  const orderId = String(order.id);
  const items = order.order_items ?? [];
  const totalQty = items.reduce((s, i) => s + (i.quantity ?? 0), 0);
  const charges = chargeRows(order, shipCosts);
  const totalFee = charges.find((c) => c.kind === "commission")?.amount ?? 0;
  const shippingCost = charges.find((c) => c.kind === "shipping")?.amount ?? 0;
  const firstItem = items[0];

  // Aggregate desired effect per internal product (orders may repeat an item)
  // and collect one line per order item for sale_items.
  const targets = new Map<string, { product_id: string; reserved: number; on_hand: number }>();
  const lines: {
    ml_item_id: string;
    product_id: string | null;
    title: string | null;
    quantity: number;
    unit_price: number;
    sale_fee: number;
  }[] = [];
  let fulfillment: Fulfillment = "reserved";
  for (const oi of items) {
    const itemId = oi.item?.id;
    const qty = Math.abs(oi.quantity ?? 1);
    if (!itemId) continue;
    const { data: listing } = await admin
      .from("ml_listings")
      .select("product_id, created_at")
      .eq("profile_id", account.profile_id)
      .eq("ml_item_id", itemId)
      .maybeSingle();

    lines.push({
      ml_item_id: itemId,
      product_id: listing?.product_id ?? null,
      title: oi.item?.title ?? null,
      quantity: qty,
      unit_price: oi.unit_price ?? 0,
      sale_fee: oi.sale_fee ?? 0,
    });

    if (!listing?.product_id) continue;

    const eff = effectFor(order.status, shipment?.status, qty);
    fulfillment = eff.fulfillment;
    // Pre-tracking orders keep a ZERO target (instead of being skipped) so
    // reconcile_order_stock compensates any double discount already applied.
    const zero = preTracking(order.date_created, listing.created_at);
    const t = targets.get(listing.product_id) ?? { product_id: listing.product_id, reserved: 0, on_hand: 0 };
    t.reserved += zero ? 0 : eff.reserved;
    t.on_hand += zero ? 0 : eff.on_hand;
    targets.set(listing.product_id, t);
  }

  // 1) Upsert the sale summary (idempotent on profile_id + ml_order_id).
  const { data: saleRow } = await admin.from("sales").upsert({
    profile_id: account.profile_id,
    ml_order_id: orderId,
    ml_item_id: firstItem?.item?.id ?? null,
    // Single-item orders keep the direct product link; multi-item orders rely
    // on sale_items (one row per product).
    product_id: lines.length === 1 ? lines[0].product_id : null,
    quantity: totalQty || 1,
    unit_price: firstItem?.unit_price ?? 0,
    currency_id: order.currency_id ?? "ARS",
    sale_fee: totalFee,
    shipping_cost: shippingCost,
    total_amount: order.total_amount ?? null,
    status: order.status,
    fulfillment_status: fulfillment,
    sold_at: order.date_created ?? null,
    raw: order as unknown as Record<string, unknown>,
  }, { onConflict: "profile_id,ml_order_id" }).select("id").single();

  // 1b) Mirror the order lines (delete+insert scoped to this sale keeps the
  // reconciliation idempotent without a partial-unique upsert).
  if (saleRow?.id && lines.length > 0) {
    await admin.from("sale_items").delete().eq("sale_id", saleRow.id);
    await admin.from("sale_items").insert(lines.map((l) => ({
      profile_id: account.profile_id,
      sale_id: saleRow.id,
      ...l,
    })));
  }

  // 1c) Mirror the typed charges (RF-39; same delete+insert idempotency).
  if (saleRow?.id) {
    await admin.from("sale_charges").delete().eq("sale_id", saleRow.id);
    if (charges.length > 0) {
      await admin.from("sale_charges").insert(charges.map((c) => ({
        profile_id: account.profile_id,
        sale_id: saleRow.id,
        ...c,
      })));
    }
  }

  // 2) Reconcile the ledger (origin=ml inside the function => no push to ML).
  // Full orders dispatch from ML's warehouse, not ours (RF-38).
  if (targets.size > 0) {
    let warehouseId: string | null = null;
    if (shipment?.logistic_type === "fulfillment") {
      const { data: fullWh, error: whErr } = await admin.rpc("ensure_full_warehouse", {
        p_profile: account.profile_id,
      });
      if (whErr) throw new Error(`ensure_full_warehouse: ${whErr.message}`);
      warehouseId = fullWh as string;
    }
    const { error } = await admin.rpc("reconcile_order_stock", {
      p_profile_id: account.profile_id,
      p_order_id: orderId,
      p_warehouse_id: warehouseId, // null => default dispatch warehouse
      p_targets: Array.from(targets.values()),
    });
    if (error) throw new Error(`reconcile_order_stock: ${error.message}`);
  }
}

/** Seller shipping costs are best-effort: the sale reconciles fine without
 * them and a later event re-reads the order and fills them in. */
async function fetchShipCosts(
  client: MeliClient | undefined,
  shipmentId: number | string | undefined,
): Promise<MeliShipmentCosts | null> {
  if (!client || shipmentId == null) return null;
  try {
    return await client.getShipmentCosts(String(shipmentId));
  } catch (_) {
    return null;
  }
}

/** Entry point for the orders_v2 topic. */
export async function processOrder(
  admin: SupabaseClient,
  account: MlAccountRow,
  order: MeliOrder,
  client?: MeliClient,
): Promise<void> {
  let shipment: MeliShipment | null = null;
  const shipId = order.shipping?.id;
  if (shipId && client) {
    try { shipment = await client.getShipment(String(shipId)); } catch (_) { /* best-effort */ }
  }
  const costs = await fetchShipCosts(client, shipId);
  await reconcileOrder(admin, account, order, shipment, costs);
}

/** Entry point for the shipments topic. */
export async function processShipment(
  admin: SupabaseClient,
  account: MlAccountRow,
  shipment: MeliShipment,
  client: MeliClient,
): Promise<void> {
  const orderId = shipment.order_id;
  if (!orderId) return;
  const order = await client.getOrder(String(orderId));
  const costs = await fetchShipCosts(client, shipment.id);
  await reconcileOrder(admin, account, order, shipment, costs);
}
