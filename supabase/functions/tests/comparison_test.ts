import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildComparison, ListingInfo } from "../_shared/comparison.ts";
import type { MeliSearchItem } from "../_shared/meli.ts";

const listing: ListingInfo = {
  ml_item_id: "MLA111",
  title: "Auriculares Bluetooth",
  price: 25000,
  category_id: "MLA1055",
  sold_quantity: 38,
  available_quantity: 10,
  seller_id: 999,
};

const results: MeliSearchItem[] = [
  // Your own item — must be excluded.
  { id: "MLA111", price: 25000, seller: { id: 999, nickname: "Yo" } },
  // Another of your listings (same seller) — excluded.
  { id: "MLA222", price: 19000, seller: { id: 999, nickname: "Yo" } },
  {
    id: "MLA333",
    price: 22900,
    currency_id: "ARS",
    permalink: "https://ml/333",
    seller: { id: 1, nickname: "TechSound Oficial" },
    shipping: { logistic_type: "fulfillment" },
  },
  {
    id: "MLA444",
    price: 24500,
    seller: { id: 2, nickname: "AudioMax Store" },
    shipping: { logistic_type: "cross_docking" },
  },
  // Junk price — excluded.
  { id: "MLA555", price: 0, seller: { id: 3, nickname: "Roto" } },
];

Deno.test("buildComparison drops own/seller/zero-price and sorts cheapest first", () => {
  const out = buildComparison(listing, results);
  assertEquals(out.your_price, 25000);
  assertEquals(out.competitors.length, 2);
  assertEquals(out.competitors[0].seller_name, "TechSound Oficial");
  assertEquals(out.competitors[0].price, 22900);
  assertEquals(out.competitors[0].is_full, true);
  assertEquals(out.competitors[0].diff_pct, -8.4); // (22900-25000)/25000*100
  assertEquals(out.competitors[1].seller_name, "AudioMax Store");
  assertEquals(out.competitors[1].is_full, false);
});

Deno.test("buildComparison falls back to a generic seller name", () => {
  const out = buildComparison(
    { ...listing, seller_id: null },
    [{ id: "X", price: 100, seller: { id: 7 } }],
  );
  assertEquals(out.competitors[0].seller_name, "Vendedor");
  assertEquals(out.competitors[0].reputation, null);
});
