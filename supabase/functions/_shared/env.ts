// Centralized environment access for Edge Functions.
export function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name) ?? fallback;
  if (v === undefined) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

export function optionalEnv(name: string): string | undefined {
  return Deno.env.get(name);
}

// MercadoLibre config (set via `supabase secrets set ...`).
export const mlConfig = () => ({
  clientId: env("ML_CLIENT_ID"),
  clientSecret: env("ML_CLIENT_SECRET"),
  redirectUri: env("ML_REDIRECT_URI"),
  siteId: env("ML_SITE_ID", "MLA"),
  apiBase: env("ML_API_BASE", "https://api.mercadolibre.com"),
  authBase: env("ML_AUTH_BASE", "https://auth.mercadolibre.com.ar"),
});

// Supabase service-role config (auto-injected in the Edge runtime).
export const supabaseConfig = () => ({
  url: env("SUPABASE_URL"),
  serviceRoleKey: env("SUPABASE_SERVICE_ROLE_KEY"),
});

// Anthropic (LLM fallback classifier). Only required by classify-product.
export const anthropicConfig = () => ({
  apiKey: env("ANTHROPIC_API_KEY"),
  model: env("ANTHROPIC_MODEL", "claude-haiku-4-5"),
  apiBase: env("ANTHROPIC_API_BASE", "https://api.anthropic.com"),
});
