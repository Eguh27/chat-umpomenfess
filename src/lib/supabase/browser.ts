import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from 'astro:env/client';

let client: SupabaseClient | undefined;

/** Client browser (anon key + sesi user). Sesi tersimpan di localStorage oleh supabase-js. */
export function getBrowserClient(): SupabaseClient {
  client ??= createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
  });
  return client;
}
