// Shared order-processing logic used by process-events and sync-orders.
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MeliClient, MeliOrder } from "./meli.ts";

export interface MlAccountRow {
  id: string;
  profile_id: string;
  ml_user_id: number;
}

/**
 * Idempotently records a sale and decrements stock for every item in the order.
 * Idempotency key: stock_movements.reference = order id (reason = 'sale').
 * Returns true if stock was applied (i.e. first time we see this order).
 */
export async function processOrder(
  admin: SupabaseClient,
  account: MlAccountRow,
  order: MeliOrder,
  client?: MeliClient,
): Promise<boolean> {
  const orderId = String(order.id);
  const firstItem = order.order_items?.[0];
  const totalQty = (order.order_items ?? []).reduce((s, i) => s + (i.quantity ?? 0), 0);
  const totalFee = (order.order_items ?? []).reduce((s, i) => s + (i.sale_fee ?? 0), 0);

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
    sold_at: order.date_created ?? null,
    raw: order as unknown as Record<string, unknown>,
  }, { onConflict: "profile_id,ml_order_id" });

  // 2) Apply stock only once per order.
  const { count } = await admin
    .from("stock_movements")
    .select("id", { count: "exact", head: true })
    .eq("reference", orderId)
    .eq("reason", "sale");
  if ((count ?? 0) > 0) return false;

  for (const oi of order.order_items ?? []) {
    const itemId = oi.item?.id;
    if (!itemId) continue;
    const { data: listing } = await admin
      .from("ml_listings")
      .select("product_id")
      .eq("profile_id", account.profile_id)
      .eq("ml_item_id", itemId)
      .maybeSingle();
    if (!listing?.product_id) continue;

    await admin.from("stock_movements").insert({
      profile_id: account.profile_id,
      product_id: listing.product_id,
      delta: -Math.abs(oi.quantity ?? 1),
      reason: "sale",
      reference: orderId,
      note: `Venta ML ${itemId}`,
    });

    // 3) Best-effort: push the new authoritative stock back to ML.
    if (client) {
      try {
        const { data: prod } = await admin
          .from("products")
          .select("current_stock")
          .eq("id", listing.product_id)
          .single();
        if (prod) await client.updateItemQuantity(itemId, Math.max(prod.current_stock, 0));
      } catch (_) { /* reconciliation is best-effort */ }
    }
  }
  return true;
}
