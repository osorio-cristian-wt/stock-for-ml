// Pure price-comparison logic (no I/O) so it can be unit-tested in isolation.
// Mirrors the `PriceComparison` model the Flutter app expects.

import type { MeliSearchItem } from "./meli.ts";

export interface CompetitorOut {
  seller_name: string;
  price: number;
  currency_id: string;
  reputation: number | null;
  is_full: boolean;
  diff_pct: number | null;
  permalink: string | null;
}

export interface ComparisonOut {
  title: string;
  your_price: number;
  category_id: string | null;
  your_sold: number;
  your_stock: number;
  competitors: CompetitorOut[];
}

export interface ListingInfo {
  ml_item_id?: string | null;
  title: string;
  price: number;
  category_id?: string | null;
  sold_quantity?: number;
  available_quantity?: number;
  /** Your ML seller id, to drop your own other publications. */
  seller_id?: number | null;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Builds the comparison payload: your listing vs. the competition inside ML,
 * cheapest first. Excludes your own item and any listing from your seller id.
 */
export function buildComparison(
  listing: ListingInfo,
  items: MeliSearchItem[],
  opts: { limit?: number } = {},
): ComparisonOut {
  const yourPrice = listing.price;
  const competitors = items
    .filter((it) => it.id !== listing.ml_item_id)
    .filter((it) => !(listing.seller_id != null && it.seller?.id === listing.seller_id))
    .filter((it) => typeof it.price === "number" && (it.price as number) > 0)
    .map<CompetitorOut>((it) => ({
      seller_name: it.seller?.nickname?.trim() || "Vendedor",
      price: it.price as number,
      currency_id: it.currency_id ?? "ARS",
      reputation: null, // ML search doesn't expose a 0–5 rating; omit honestly
      is_full: it.shipping?.logistic_type === "fulfillment",
      diff_pct: yourPrice > 0
        ? round2(((it.price as number) - yourPrice) / yourPrice * 100)
        : null,
      permalink: it.permalink ?? null,
    }))
    .sort((a, b) => a.price - b.price)
    .slice(0, opts.limit ?? 8);

  return {
    title: listing.title,
    your_price: yourPrice,
    category_id: listing.category_id ?? null,
    your_sold: listing.sold_quantity ?? 0,
    your_stock: listing.available_quantity ?? 0,
    competitors,
  };
}
