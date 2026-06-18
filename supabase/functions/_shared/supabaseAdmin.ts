import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { supabaseConfig } from "./env.ts";

// Service-role client: bypasses RLS. Use ONLY inside trusted Edge Functions.
export function createAdminClient(): SupabaseClient {
  const { url, serviceRoleKey } = supabaseConfig();
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
