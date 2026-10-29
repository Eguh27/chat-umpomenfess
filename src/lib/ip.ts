import { createHmac } from 'node:crypto';
import { isIPv4, isIPv6 } from 'node:net';

/**
 * Normalisasi IP untuk lockout:
 * - IPv4 apa adanya.
 * - IPv4-mapped IPv6 (::ffff:1.2.3.4) -> IPv4.
 * - IPv6 -> prefix /64 (satu pengguna bisa punya jutaan alamat dalam satu /64).
 */
export function normalizeIp(raw: string): string {
  const ip = raw.trim().split('%')[0]; // buang zone id
  if (isIPv4(ip)) return ip;
  if (!isIPv6(ip)) throw new Error('invalid ip');

  const mapped = ip.toLowerCase().match(/^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (mapped && isIPv4(mapped[1])) return mapped[1];

  // Ekspansi "::" menjadi 8 hextet
  const [head, tail] = ip.split('::');
  const h = head ? head.split(':') : [];
  const t = tail !== undefined && tail !== '' ? tail.split(':') : [];
  const missing = 8 - h.length - t.length;
  const full = ip.includes('::') ? [...h, ...Array(missing).fill('0'), ...t] : h;
  if (full.length !== 8) throw new Error('invalid ipv6');
  const prefix = full.slice(0, 4).map((x) => x.padStart(4, '0').toLowerCase());
  return prefix.join(':') + '::/64';
}

/** HMAC-SHA256(salt, normalizedIp) -> hex. Hanya hash ini yang boleh disimpan. */
export function hashIp(raw: string, salt: string): string {
  if (!salt || salt.length < 32) throw new Error('IP_HASH_SALT must be >= 32 chars');
  return createHmac('sha256', salt).update(normalizeIp(raw)).digest('hex');
}
