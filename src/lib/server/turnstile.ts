import { TURNSTILE_SECRET_KEY } from 'astro:env/server';

/** Verifikasi token Cloudflare Turnstile di sisi server. */
export async function verifyTurnstile(token: string, remoteIp?: string): Promise<boolean> {
  if (!TURNSTILE_SECRET_KEY) throw new Error('TURNSTILE_SECRET_KEY belum diset');
  const body = new URLSearchParams({ secret: TURNSTILE_SECRET_KEY, response: token });
  if (remoteIp) body.set('remoteip', remoteIp);
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    body,
  });
  if (!res.ok) return false;
  const json = (await res.json()) as { success?: boolean };
  return json.success === true;
}
