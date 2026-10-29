# umpomenfess-room

Room chat anonim (Project 3 UMPOMENFESS). Astro SSR + Vercel + Supabase (Postgres/Auth/Realtime).

## Mulai

```bash
npm install
cp .env.example .env     # isi nilai (lihat docs/setup.md)
npm run dev
npm run lint && npm test && npm run check && npm run build
```

Butuh Node ≥ 22.22. Database lokal: `supabase start` (Docker), `supabase db reset`.

## Peta dokumen

- `AGENTS.md` — aturan permanen, peran, zona tulis
- `TASK.md` — spesifikasi dan kontrak (sumber kebenaran)
- `TODO.md` — papan tugas bergelombang
- `docs/prompts/` — prompt per agent (mulai dari `README.md`)
- `docs/setup.md` — langkah manual (akun Supabase/Vercel/Turnstile/DNS)
- `docs/progress.md` — log serah-terima
- `docs/PRD_v2.docx` — PRD sebelumnya (TASK.md lebih baru bila berbeda)

## Status

Kerangka siap. Migration, RPC, dan UI belum dibuat. Mulai dari Wave 1 di `TODO.md`.
