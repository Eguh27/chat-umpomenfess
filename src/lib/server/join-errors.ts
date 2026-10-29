export type JoinErrorBody = {
  error: string;
  retryAfter?: number;
};

export type JoinErrorMapping = {
  status: number;
  body: JoinErrorBody;
  headers?: Record<string, string>;
};

const FORBIDDEN_CODES = new Set([
  'ROOM_FULL',
  'MAX_ROOMS_PER_GUEST',
  'KICKED',
  'REJECTED',
  'ROOM_CLOSED',
]);

/** DETAIL dari Postgres berupa JSON, mis. {"retry_after":600}. */
export function parseRetryAfter(details: string | null | undefined): number | null {
  if (!details) return null;
  try {
    const parsed: unknown = JSON.parse(details);
    if (typeof parsed !== 'object' || parsed === null) return null;
    const value = (parsed as { retry_after?: unknown }).retry_after;
    const seconds = typeof value === 'number' ? value : Number(value);
    if (!Number.isFinite(seconds) || seconds <= 0) return null;
    return Math.ceil(seconds);
  } catch {
    return null;
  }
}

/** Memetakan kode error RPC join_room ke respons HTTP. */
export function mapJoinError(
  code: string,
  details?: string | null,
): JoinErrorMapping {
  if (code === 'WRONG_PASSWORD') {
    return { status: 401, body: { error: code } };
  }

  if (code === 'LOCKED' || code === 'ROOM_COOLDOWN') {
    const retryAfter = parseRetryAfter(details);
    return {
      status: 429,
      body: retryAfter ? { error: code, retryAfter } : { error: code },
      headers: retryAfter ? { 'retry-after': String(retryAfter) } : undefined,
    };
  }

  if (FORBIDDEN_CODES.has(code)) {
    return { status: 403, body: { error: code } };
  }

  if (code === 'ROOM_NOT_FOUND') {
    return { status: 404, body: { error: code } };
  }

  if (code === 'INVALID_INPUT') {
    return { status: 400, body: { error: code } };
  }

  // Jangan bocorkan detail internal ke client.
  return { status: 500, body: { error: 'SERVER_ERROR' } };
}
