import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { supabaseConfig } from "./env.ts";

// Service-role client: bypasses RLS. Use ONLY inside trusted Edge Functions.
export function createAdminClient(): SupabaseClient {
  const { url, serviceRoleKey } = supabaseConfig();
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// Validates an app user's JWT against GoTrue using the service-role key.
export async function getUserFromJwt(jwt: string) {
  const { url, serviceRoleKey } = supabaseConfig();
  const authClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await authClient.auth.getUser(jwt);
  if (error || !data.user) return null;
  return data.user;
}
