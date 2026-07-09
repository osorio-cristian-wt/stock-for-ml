import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chargeRows } from "../_shared/orders.ts";
import { isFulfillment } from "../_shared/items.ts";
import { MeliItem, MeliOrder, MeliShipmentCosts } from "../_shared/meli.ts";

function order(overrides: Partial<MeliOrder> = {}): MeliOrder {
  return {
    id: 2000001,
    status: "paid",
    date_created: "2026-07-08T12:00:00Z",
    currency_id: "ARS",
    total_amount: 30000,
    seller: { id: 111 },
    order_items: [
      { item: { id: "MLA1", title: "Prod" }, quantity: 1, unit_price: 30000, sale_fee: 3900 },
    ],
    ...overrides,
  };
}

Deno.test("chargeRows: commission is PER UNIT times quantity", () => {
  const rows = chargeRows(
    order({
      order_items: [
        { item: { id: "MLA1", title: "A" }, quantity: 3, unit_price: 10000, sale_fee: 1300 },
        { item: { id: "MLA2", title: "B" }, quantity: 1, unit_price: 5000, sale_fee: 650 },
      ],
    }),
    null,
  );
  const commission = rows.find((r) => r.kind === "commission");
  assertEquals(commission?.amount, 1300 * 3 + 650);
  assertEquals(commission?.source, "order");
});

Deno.test("chargeRows: seller shipping cost comes from senders[].cost", () => {
  const costs: MeliShipmentCosts = {
    gross_amount: 8000,
    senders: [{ user_id: 111, cost: 5200, save: 800 }],
    receiver: { user_id: 222, cost: 0 },
  };
  const rows = chargeRows(order(), costs);
  const shipping = rows.find((r) => r.kind === "shipping");
  assertEquals(shipping?.amount, 5200);
  assertEquals(shipping?.source, "shipment");
});

Deno.test("chargeRows: ignores other senders' costs (multi-seller cart)", () => {
  const costs: MeliShipmentCosts = {
    senders: [
      { user_id: 111, cost: 5200 },
      { user_id: 999, cost: 4000 },
    ],
  };
  const rows = chargeRows(order(), costs);
  assertEquals(rows.find((r) => r.kind === "shipping")?.amount, 5200);
});

Deno.test("chargeRows: order taxes become a tax charge", () => {
  const rows = chargeRows(
    order({ taxes: { amount: 630, currency_id: "ARS" } }),
    null,
  );
  const tax = rows.find((r) => r.kind === "tax");
  assertEquals(tax?.amount, 630);
  assertEquals(tax?.currency_id, "ARS");
});

Deno.test("chargeRows: free order with no costs yields no rows", () => {
  const rows = chargeRows(
    order({ order_items: [{ item: { id: "MLA1", title: "A" }, quantity: 1, unit_price: 100 }] }),
    { senders: [{ user_id: 111, cost: 0 }] },
  );
  assertEquals(rows, []);
});

Deno.test("isFulfillment detects Full-managed items", () => {
  const base = {
    id: "MLA1",
    title: "x",
    category_id: "MLA123",
    listing_type_id: "gold_special",
    price: 1,
    currency_id: "ARS",
    available_quantity: 1,
    sold_quantity: 0,
    status: "active",
    permalink: "",
    thumbnail: "",
  } as MeliItem;
  assertEquals(isFulfillment({ ...base, shipping: { logistic_type: "fulfillment" } }), true);
  assertEquals(isFulfillment({ ...base, shipping: { logistic_type: "cross_docking" } }), false);
  assertEquals(isFulfillment(base), false);
});
