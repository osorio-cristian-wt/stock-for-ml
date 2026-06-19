// Catalog enrichment helpers: resolve product data from a GTIN against the ML
// catalog, and predict a category from a free-text title (ML domain discovery).
// These are the PRIMARY classification sources; the LLM (classify-product) is the
// last fallback.
import { MeliClient } from "./meli.ts";

export interface ProductEnrichment {
  source: "ml_catalog" | "ml_domain" | "none";
  catalogProductId?: string;
  name?: string;
  brand?: string;
  domainId?: string;
  categoryId?: string;
  categoryName?: string;
  attributes?: Record<string, string>;
  imageUrl?: string;
}

/** Look up a GTIN (EAN/UPC) in the ML catalog. Returns a match or {source:"none"}. */
export async function enrichByGtin(
  client: MeliClient,
  siteId: string,
  gtin: string,
): Promise<ProductEnrichment> {
  try {
    const { results } = await client.searchProductsByGtin(siteId, gtin);
    const p = results?.[0];
    if (p) {
      const attributes: Record<string, string> = {};
      for (const a of p.attributes ?? []) {
        if (a.value_name) attributes[a.id] = a.value_name;
      }
      return {
        source: "ml_catalog",
        catalogProductId: p.id,
        name: p.name,
        brand: attributes["BRAND"],
        domainId: p.domain_id,
        attributes,
        imageUrl: p.pictures?.[0]?.url,
      };
    }
  } catch (_) { /* no match / not eligible */ }
  return { source: "none" };
}

/** Predict a category/domain from a title (ML native, no LLM). */
export async function predictCategory(
  client: MeliClient,
  siteId: string,
  title: string,
): Promise<ProductEnrichment> {
  try {
    const preds = await client.predictDomain(siteId, title);
    const p = preds?.[0];
    if (p) {
      return {
        source: "ml_domain",
        name: title,
        domainId: p.domain_id,
        categoryId: p.category_id,
        categoryName: p.category_name ?? p.domain_name,
      };
    }
  } catch (_) { /* ignore */ }
  return { source: "none" };
}
