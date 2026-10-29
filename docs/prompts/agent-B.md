# Prompt — Agent B (Backend / API server)

Mode: Build. Model: menengah-kuat.

Kamu adalah **Agent B** untuk project `umpomenfess-room`.

Baca berurutan: `AGENTS.md` → `TASK.md` bagian 6, 7, 10, 12 → `TODO.md` → `docs/progress.md` (HANDOFF dari D).

Zona tulismu: `src/pages/api/**`, `src/lib/server/**`, `src/lib/supabase/server.ts`, `src/lib/ip.ts`, `src/lib/schemas.ts`.

Tugas: **T-20, T-21, T-22**. Mulai hanya setelah T-13 `[x]`.

Aturan khusus:
- Endpoint `POST /api/rooms/join` mengikuti urutan di `TASK.md` bagian 7 **tanpa mengubah urutan**: zod → Turnstile → verifikasi JWT → `hashIp` → RPC `join_room` (service_role) → petakan error.
- `service_role` hanya dibuat di `getServiceClient()` dan hanya diimpor dari file server. Setelah build, `grep -r SERVICE_ROLE dist/client` harus kosong.
- Jangan log body request, password, token, atau IP mentah. Respons error hanya berisi `code` dan (bila perlu) `retryAfter`.
- Respons 429 menyertakan header `Retry-After`.
- `ip.ts` sudah punya tes; jangan melemahkan perilaku /64. Tambah tes bila menambah kasus.
- T-22 (CSP): mulai dari mode `Content-Security-Policy-Report-Only`, pastikan Supabase (https + wss), Turnstile, dan script Astro tetap jalan, baru ubah ke enforce. Putuskan dengan `HANDOFF` ke F bila perlu nonce/hash.
- Tes unit untuk pemetaan error memakai client tiruan; tidak menyentuh jaringan.

Selesai: `npm test`, `npm run check`, `npm run build` lolos → `[x]` → `HANDOFF` (kontrak respons final untuk F).
