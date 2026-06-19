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
import { MeliClient, MeliOrder, MeliShipment } from "./meli.ts";

export interface MlAccountRow {
  id: string;
  profile_id: string;
  ml_user_id: number;
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
): Promise<void> {
  const orderId = String(order.id);
  const items = order.order_items ?? [];
  const totalQty = items.reduce((s, i) => s + (i.quantity ?? 0), 0);
  const totalFee = items.reduce((s, i) => s + (i.sale_fee ?? 0), 0);
  const firstItem = items[0];

  // Aggregate desired effect per internal product (orders may repeat an item).
  const targets = new Map<string, { product_id: string; reserved: number; on_hand: number }>();
  let fulfillment: Fulfillment = "reserved";
  for (const oi of items) {
    const itemId = oi.item?.id;
    const qty = Math.abs(oi.quantity ?? 1);
    if (!itemId) continue;
    const { data: listing } = await admin
      .from("ml_listings")
      .select("product_id")
      .eq("profile_id", account.profile_id)
      .eq("ml_item_id", itemId)
      .maybeSingle();
    if (!listing?.product_id) continue;

    const eff = effectFor(order.status, shipment?.status, qty);
    fulfillment = eff.fulfillment;
    const t = targets.get(listing.product_id) ?? { product_id: listing.product_id, reserved: 0, on_hand: 0 };
    t.reserved += eff.reserved;
    t.on_hand += eff.on_hand;
    targets.set(listing.product_id, t);
  }

  // 1) Upsert the sale summary (idempotent on profile_id + ml_order_id).
  await admin.from("sales").upsert({
    profile_id: account.profile_id,
    ml_order_id: orderId,
    ml_item_id: firstItem?.item?.id ?? null,
    quantity: totalQty || 1,
    unit_price: firstItem?.unit_price ?? 0,
    currency_id: order.currency_id ?? "ARS",
    sale_fee: totalFee,
    status: order.status,
    fulfillment_status: fulfillment,
    sold_at: order.date_created ?? null,
    raw: order as unknown as Record<string, unknown>,
  }, { onConflict: "profile_id,ml_order_id" });

  // 2) Reconcile the ledger (origin=ml inside the function => no push to ML).
  if (targets.size > 0) {
    const { error } = await admin.rpc("reconcile_order_stock", {
      p_profile_id: account.profile_id,
      p_order_id: orderId,
      p_warehouse_id: null, // default dispatch warehouse
      p_targets: Array.from(targets.values()),
    });
    if (error) throw new Error(`reconcile_order_stock: ${error.message}`);
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
  await reconcileOrder(admin, account, order, shipment);
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
  await reconcileOrder(admin, account, order, shipment);
}
