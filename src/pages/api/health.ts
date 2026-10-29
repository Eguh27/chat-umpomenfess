import type { APIRoute } from 'astro';
import { getServiceClient } from '../../lib/supabase/server';

export const prerender = false;

/** GET /api/health      -> {ok:true}
 *  GET /api/health?db=1 -> juga membaca 1 baris dari DB (dipakai keep-alive agar proyek Supabase free tidak di-pause). */
export const GET: APIRoute = async ({ url }) => {
  const body: Record<string, unknown> = { ok: true, time: new Date().toISOString() };
  if (url.searchParams.get('db') === '1') {
    try {
      const { error } = await getServiceClient().from('tier_limits').select('tier').limit(1);
      body.db = error ? 'error' : 'ok';
    } catch {
      body.db = 'error';
    }
  }
  return new Response(JSON.stringify(body), {
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
};
