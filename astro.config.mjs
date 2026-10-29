// @ts-check
import { defineConfig, envField } from 'astro/config';
import vercel from '@astrojs/vercel';
import react from '@astrojs/react';

// SSR di Vercel. Rahasia server HANYA lewat astro:env (access: 'secret', context: 'server').
// Jangan pernah memakai awalan PUBLIC_ untuk service role key atau secret lain.
export default defineConfig({
  output: 'server',
  adapter: vercel(),
  integrations: [react()],
  security: { checkOrigin: true },
  env: {
    schema: {
      PUBLIC_SUPABASE_URL: envField.string({ context: 'client', access: 'public' }),
      PUBLIC_SUPABASE_ANON_KEY: envField.string({ context: 'client', access: 'public' }),
      PUBLIC_TURNSTILE_SITE_KEY: envField.string({ context: 'client', access: 'public' }),
      SUPABASE_SERVICE_ROLE_KEY: envField.string({
        context: 'server',
        access: 'secret',
        optional: true,
      }),
      TURNSTILE_SECRET_KEY: envField.string({
        context: 'server',
        access: 'secret',
        optional: true,
      }),
      IP_HASH_SALT: envField.string({ context: 'server', access: 'secret', optional: true }),
    },
  },
});
