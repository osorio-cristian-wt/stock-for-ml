// MercadoLibre API client (Deno/TypeScript).
// ML deprecated its official SDKs in 2021, so this is a small purpose-built
// client covering OAuth + the endpoints this project needs.

export interface MeliTokens {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number; // seconds
  scope?: string;
  user_id?: number;
}

export interface AuthorizeUrlParams {
  authBase: string; // e.g. https://auth.mercadolibre.com.ar
  clientId: string;
  redirectUri: string;
  state: string;
  codeChallenge?: string;
}

/** Build the ML authorization URL (server-side Authorization Code + PKCE). */
export function buildAuthorizeUrl(p: AuthorizeUrlParams): string {
  const url = new URL("/authorization", p.authBase);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", p.clientId);
  url.searchParams.set("redirect_uri", p.redirectUri);
  url.searchParams.set("state", p.state);
  if (p.codeChallenge) {
    url.searchParams.set("code_challenge", p.codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
  }
  return url.toString();
}

export interface OAuthExchangeParams {
  apiBase: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  code: string;
  codeVerifier?: string;
}

/** Exchange an authorization code for tokens. */
export async function exchangeCodeForToken(p: OAuthExchangeParams): Promise<MeliTokens> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: p.clientId,
    client_secret: p.clientSecret,
    code: p.code,
    redirect_uri: p.redirectUri,
  });
  if (p.codeVerifier) body.set("code_verifier", p.codeVerifier);
  return await postToken(p.apiBase, body);
}

export interface RefreshParams {
  apiBase: string;
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}

/** Exchange a (single-use) refresh token for a new token pair. */
export async function refreshAccessToken(p: RefreshParams): Promise<MeliTokens> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: p.clientId,
    client_secret: p.clientSecret,
    refresh_token: p.refreshToken,
  });
  return await postToken(p.apiBase, body);
}

async function postToken(apiBase: string, body: URLSearchParams): Promise<MeliTokens> {
  const res = await fetch(`${apiBase}/oauth/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json",
    },
    body,
  });
  if (!res.ok) {
    throw new Error(`ML token endpoint ${res.status}: ${await res.text()}`);
  }
  return await res.json() as MeliTokens;
}

/** Authenticated client for the ML REST API. */
export class MeliClient {
  constructor(
    private accessToken: string,
    private apiBase = "https://api.mercadolibre.com",
  ) {}

  private async req<T>(path: string, init: RequestInit = {}): Promise<T> {
    const res = await fetch(`${this.apiBase}${path}`, {
      ...init,
      headers: {
        "Authorization": `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(init.headers ?? {}),
      },
    });
    if (res.status === 429) throw new Error("ML rate limit (429)");
    if (!res.ok) throw new Error(`ML ${path} -> ${res.status}: ${await res.text()}`);
    return await res.json() as T;
  }

  getMe(): Promise<{ id: number; nickname: string; site_id: string }> {
    return this.req("/users/me");
  }

  /** Paged list of the seller's item ids. */
  searchUserItems(userId: number, offset = 0, limit = 50): Promise<{ results: string[]; paging: { total: number } }> {
    return this.req(`/users/${userId}/items/search?offset=${offset}&limit=${limit}`);
  }

  getItem(itemId: string): Promise<MeliItem> {
    return this.req(`/items/${itemId}`);
  }

  /** Update the available stock of an item. */
  updateItemQuantity(itemId: string, quantity: number): Promise<MeliItem> {
    return this.req(`/items/${itemId}`, {
      method: "PUT",
      body: JSON.stringify({ available_quantity: quantity }),
    });
  }

  updateItemPrice(itemId: string, price: number): Promise<MeliItem> {
    return this.req(`/items/${itemId}`, {
      method: "PUT",
      body: JSON.stringify({ price }),
    });
  }

  getOrder(orderId: string): Promise<MeliOrder> {
    return this.req(`/orders/${orderId}`);
  }

  searchOrders(sellerId: number, offset = 0, limit = 50): Promise<{ results: MeliOrder[] }> {
    return this.req(`/orders/search?seller=${sellerId}&sort=date_desc&offset=${offset}&limit=${limit}`);
  }

  /** Read-only listing fees for a category/price. */
  getListingPrices(siteId: string, price: number, categoryId?: string, listingTypeId?: string): Promise<MeliListingPrice[]> {
    const qs = new URLSearchParams({ price: String(price) });
    if (categoryId) qs.set("category_id", categoryId);
    if (listingTypeId) qs.set("listing_type_id", listingTypeId);
    return this.req(`/sites/${siteId}/listing_prices?${qs.toString()}`);
  }
}

// ── Lightweight response types (only the fields we use) ──────────────
export interface MeliItem {
  id: string;
  title: string;
  category_id: string;
  listing_type_id: string;
  price: number;
  currency_id: string;
  available_quantity: number;
  sold_quantity: number;
  status: string;
  permalink: string;
  thumbnail: string;
  variations?: { id: number; price: number; available_quantity: number; attribute_combinations: unknown[] }[];
}

export interface MeliOrderItem {
  item: { id: string; title: string };
  quantity: number;
  unit_price: number;
  sale_fee?: number;
}

export interface MeliOrder {
  id: number;
  status: string;
  date_created: string;
  currency_id: string;
  total_amount: number;
  seller: { id: number };
  order_items: MeliOrderItem[];
  payments?: { total_paid_amount: number }[];
}

export interface MeliListingPrice {
  listing_type_id: string;
  sale_fee_amount: number;
  sale_fee_details?: Record<string, number>;
}
