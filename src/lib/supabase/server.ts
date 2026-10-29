import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from 'astro:env/client';
import { SUPABASE_SERVICE_ROLE_KEY } from 'astro:env/server';

/** Hasil RPC join_room sesuai kontrak TASK.md bagian 6. */
export type JoinRoomRow = {
  status: 'PENDING' | 'APPROVED';
  room_id: string;
  member_id: string;
  display_name: string;
};

function requireEnv(value: string | undefined, name: string): string {
  if (!value) throw new Error(`${name} belum diset`);
  return value;
}

/** HANYA untuk kode server (API route). Memakai service_role: melewati RLS. */
export function getServiceClient(): SupabaseClient {
  const url = requireEnv(PUBLIC_SUPABASE_URL, 'PUBLIC_SUPABASE_URL');
  const key = requireEnv(SUPABASE_SERVICE_ROLE_KEY, 'SUPABASE_SERVICE_ROLE_KEY');
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Client dengan kunci publik; dipakai server hanya untuk memverifikasi access token. */
export function getAnonClient(): SupabaseClient {
  const url = requireEnv(PUBLIC_SUPABASE_URL, 'PUBLIC_SUPABASE_URL');
  const key = requireEnv(PUBLIC_SUPABASE_ANON_KEY, 'PUBLIC_SUPABASE_ANON_KEY');
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Memverifikasi access token milik pemanggil; mengembalikan user id atau null. */
export async function verifyAccessToken(token: string): Promise<string | null> {
  if (!token) return null;
  const { data, error } = await getAnonClient().auth.getUser(token);
  return error || !data.user ? null : data.user.id;
}
