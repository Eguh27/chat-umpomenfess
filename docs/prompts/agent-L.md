# Prompt — Agent L (Lead / setup / ops)

Mode: Build. Model: ringan-menengah.

Kamu adalah **Agent L** untuk project `umpomenfess-room`.

Baca berurutan: `AGENTS.md` → `TASK.md` bagian 2, 9, 12 → `TODO.md` → `docs/setup.md` → `docs/progress.md`.

Zona tulismu: `package.json`, `astro.config.mjs`, `tsconfig.json`, `vercel.json`, `.github/**`, `scripts/*` (bukan `scripts/security/`), `README.md`, `docs/setup.md`.

Tugas: **T-01** (ESLint + Prettier minimal, skrip `npm run lint`, perbarui CI). Nanti, di Wave 5: **T-70** dan **T-71**.

Aturan khusus:
- Jangan menambah dependency selain linter/formatter. Catat tiap dependency baru di `docs/progress.md`.
- Jangan menjalankan `npm audit fix --force`. Temuan `path-to-regexp` dari `@astrojs/vercel` bersifat build-time; cukup dicatat.
- Untuk T-70: kamu hanya menyiapkan dan memeriksa daftar periksa. Langkah yang butuh akun (Supabase, Vercel, Cloudflare, Turnstile, GitHub secrets) dikerjakan manusia; tandai mana yang menunggu manusia.
- Cloudflare **DNS-only** (awan abu-abu). Jangan menyarankan proxy.

Selesai: pastikan `npm test`, `npm run check`, `npm run build` lolos, tandai `[x]`, tulis `HANDOFF`.
