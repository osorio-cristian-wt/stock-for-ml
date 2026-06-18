import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { computeEconomics } from "../_shared/economics.ts";

Deno.test("computeEconomics matches the seeded headphones figures", () => {
  // 8.50 USD * 1200 = 10200 ARS cost; price 25000, fee 3000.
  const e = computeEconomics({ salePrice: 25000, estSaleFee: 3000, purchaseCost: 8.5, fxRate: 1200 });
  assertEquals(e.costInSaleCurrency, 10200);
  assertEquals(e.netProfit, 11800);
  assertEquals(e.markupPct, 115.69);
  assertEquals(e.marginPct, 47.2);
});

Deno.test("computeEconomics returns null ratios when cost/price are zero", () => {
  const e = computeEconomics({ salePrice: 0, estSaleFee: 0, purchaseCost: 0, fxRate: 1200 });
  assertEquals(e.markupPct, null);
  assertEquals(e.marginPct, null);
});

Deno.test("computeEconomics can produce a loss", () => {
  const e = computeEconomics({ salePrice: 1000, estSaleFee: 200, purchaseCost: 1, fxRate: 1200 });
  assertEquals(e.costInSaleCurrency, 1200);
  assertEquals(e.netProfit, -400);
});
