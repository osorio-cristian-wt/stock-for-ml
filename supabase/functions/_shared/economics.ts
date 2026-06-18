// Pure profit math — mirrors the SQL view public.v_product_economics.
// Kept dependency-free so it can be unit tested in isolation.

export interface EconomicsInput {
  /** Sale price in the listing currency (e.g. ARS). */
  salePrice: number;
  /** Estimated ML sale fee in the listing currency. */
  estSaleFee: number;
  /** Purchase cost in its own currency (e.g. USD). */
  purchaseCost: number;
  /** FX rate to convert purchaseCost into the listing currency (e.g. USD->ARS). */
  fxRate: number;
}

export interface Economics {
  costInSaleCurrency: number;
  netProfit: number;
  /** Profit over cost, as a percentage. null when cost is 0. */
  markupPct: number | null;
  /** Profit over sale price, as a percentage. null when price is 0. */
  marginPct: number | null;
}

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export function computeEconomics(input: EconomicsInput): Economics {
  const { salePrice, estSaleFee, purchaseCost, fxRate } = input;
  const costInSaleCurrency = round2(purchaseCost * fxRate);
  const netProfit = round2(salePrice - estSaleFee - costInSaleCurrency);
  return {
    costInSaleCurrency,
    netProfit,
    markupPct: costInSaleCurrency > 0 ? round2((netProfit / costInSaleCurrency) * 100) : null,
    marginPct: salePrice > 0 ? round2((netProfit / salePrice) * 100) : null,
  };
}
