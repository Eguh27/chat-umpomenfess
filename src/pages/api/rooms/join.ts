import type { APIRoute } from 'astro';
import type { SupabaseClient } from '@supabase/supabase-js';
import { IP_HASH_SALT, TURNSTILE_SECRET_KEY } from 'astro:env/server';
import { hashIp } from '../../../lib/ip';
import { joinRequestSchema } from '../../../lib/schemas';
import { mapJoinError } from '../../../lib/server/join-errors';
import { verifyTurnstile } from '../../../lib/server/turnstile';
import {
  getServiceClient,
  verifyAccessToken,
  type JoinRoomRow,
} from '../../../lib/supabase/server';

export const prerender = false;

function json(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      ...headers,
    },
  });
}

function getBearerToken(request: Request): string | null {
  const header = request.headers.get('authorization');
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token || null;
}

/**
 * Catat kegagalan password di statement terpisah. join_room melakukan
 * RAISE EXCEPTION sehingga tulisannya sendiri di-rollback.
 */
async function recordJoinFailure(
  service: SupabaseClient,
  slug: string,
  ipHash: string,
): Promise<void> {
  try {
    const { error } = await service.rpc('record_join_failure', {
      p_slug: slug,
      p_ip_hash: ipHash,
    });
    if (error) console.error('record_join_failure failed', error.code);
  } catch {
    // Jangan pernah mencatat password/IP mentah. Kegagalan pencatatan
    // tidak boleh mengubah respons 401 ke client.
    console.error('record_join_failure failed');
  }
}

/**
 * POST /api/rooms/join — kontrak TASK.md bagian 7.
 * Turnstile hanya dilewati di development bila secret belum diisi;
 * build produksi selalu mewajibkan TURNSTILE_SECRET_KEY.
 */
export const POST: APIRoute = async ({ request, clientAddress }) => {
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return json({ error: 'INVALID_INPUT' }, 400);
  }

  const parsed = joinRequestSchema.safeParse(payload);
  if (!parsed.success) {
    return json({ error: 'INVALID_INPUT' }, 400);
  }

  const { slug, password, turnstileToken } = parsed.data;

  if (!clientAddress) {
    return json({ error: 'SERVER_ERROR' }, 500);
  }

  if (TURNSTILE_SECRET_KEY) {
    let turnstileOk = false;
    try {
      turnstileOk = await verifyTurnstile(turnstileToken, clientAddress);
    } catch {
      turnstileOk = false;
    }
    if (!turnstileOk) {
      return json({ error: 'TURNSTILE_FAILED' }, 403);
    }
  } else if (!import.meta.env.DEV) {
    // Jangan pernah membuka join tanpa Turnstile di production.
    return json({ error: 'SERVER_ERROR' }, 500);
  }

  const accessToken = getBearerToken(request);
  if (!accessToken) {
    return json({ error: 'UNAUTHORIZED' }, 401);
  }

  let userId: string | null;
  try {
    userId = await verifyAccessToken(accessToken);
  } catch {
    return json({ error: 'SERVER_ERROR' }, 500);
  }
  if (!userId) {
    return json({ error: 'UNAUTHORIZED' }, 401);
  }

  let ipHash: string;
  try {
    ipHash = hashIp(clientAddress, IP_HASH_SALT ?? '');
  } catch {
    return json({ error: 'SERVER_ERROR' }, 500);
  }

  let service: SupabaseClient;
  try {
    service = getServiceClient();
  } catch {
    return json({ error: 'SERVER_ERROR' }, 500);
  }

  let rows: JoinRoomRow[] | null;
  let rpcError: { message: string; details: string | null } | null;
  try {
    const result = await service.rpc('join_room', {
      p_user_id: userId,
      p_slug: slug,
      p_password: password,
      p_ip_hash: ipHash,
    });
    // RPC SETOF selalu mengembalikan array; validasi bentuk sebelum dipakai.
    rows = Array.isArray(result.data) ? (result.data as JoinRoomRow[]) : null;
    rpcError = result.error;
  } catch {
    return json({ error: 'SERVER_ERROR' }, 500);
  }

  if (rpcError) {
    if (rpcError.message === 'WRONG_PASSWORD') {
      await recordJoinFailure(service, slug, ipHash);
    }
    const mapped = mapJoinError(rpcError.message, rpcError.details);
    return json(mapped.body, mapped.status, mapped.headers);
  }

  const row = rows?.[0];
  if (!row) {
    return json({ error: 'SERVER_ERROR' }, 500);
  }

  return json({
    status: row.status,
    roomId: row.room_id,
    memberId: row.member_id,
    displayName: row.display_name,
  });
};
