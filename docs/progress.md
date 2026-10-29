# Progress & serah-terima (append-only)

Format entri:
`## YYYY-MM-DD HH:MM — [PERAN] TIPE T-xx` dengan TIPE = `HANDOFF` | `REQUEST` | `BLOCKER` | `DECISION` | `NOTE`.
Isi singkat: apa yang dibuat/diminta, file terkait, cara tes, hal yang perlu diketahui agent berikutnya.

---

## 2026-10-23 — [L] HANDOFF T-00
- Kerangka dibuat dan diverifikasi: `npm test` (5 tes `ip.ts` lolos), `npm run check` (0 error), `npm run build` (lolos), `grep` bundle client tidak berisi nama secret.
- Versi terpasang: Astro 7.4.1, @astrojs/vercel 11, @astrojs/react 7, React 19, supabase-js 2.x, zod 4, vitest 5. Node ≥ 22.22 diperlukan.
- Belum ada: migration SQL, RPC, UI nyata, endpoint join (stub 501). Semuanya dikerjakan sesuai `TODO.md`.
- `design/tokens.css` masih placeholder; hanya `--brand: #BFE8EA` yang asli.
- `npm audit`: 3 temuan high (`path-to-regexp` via adapter Vercel, build-time). Jangan `audit fix --force`.
- Angka tier/kuota di `TASK.md` bagian 3 masih USULAN.

## 2026-10-24 12:50 — [D] HANDOFF T-10..T-15
- Migration selesai: `supabase/migrations/0001_init_schema.sql` … `0005_cron_realtime.sql`. Seed dev: `supabase/seed.sql`.
- Tes pgTAP: `supabase/tests/rpc/100_host_rpc.test.sql` (37), `200_guest_rpc.test.sql` (62), `300_catalog.test.sql` (24). Hasil `supabase test db`: **123 tests PASS**.
- Verifikasi lain: `supabase db reset` sukses; `npm test` 5/5; `npm run check` 0 error; `npm run build` sukses (env `PUBLIC_*` diisi lokal). `grep -r SERVICE_ROLE dist/client` kosong.
- Seed: Host `dev@example.com` / `devpassword`, Host kedua `dev2@example.com`; room `devroom000000001` password `ABC234`. Hanya untuk lokal.
- RPC Host final: `create_room(p_name,p_max_guests,p_approval_required,p_idle_timeout_minutes,p_typing_enabled)` → `room_id,slug,password,expires_at`; `regenerate_password(p_room_id)` → `password`; `update_room_settings(p_room_id,p_approval_required,p_max_guests,p_idle_timeout_minutes,p_typing_enabled)` → kolom room aman (tanpa `password_hash`); `close_room(p_room_id)`; `decide_member(p_member_id,p_decision)` → `id,display_name,status`; `kick_member(p_member_id)`; `list_members(p_room_id)` → `id,display_name,status,created_at`; `list_hosted_rooms()` → room + `typing_effective`, `approved_count`, `pending_count`, `quota`; `export_messages(p_room_id,p_after_id=0,p_limit=1000)`.
- RPC Guest final: `get_room_public(p_slug)` → `room_id,name,status,typing_effective`; `rejoin_room(p_room_id)` → `member_status`; `my_rooms()` → `room_id,slug,name,room_status,my_status,display_name,expires_at`; `list_messages(p_room_id,p_before_id=null,p_after_id=null,p_limit=50)`; `send_message(p_room_id,p_content,p_client_msg_id)` → baris pesan (idempotent); `touch_activity(p_room_id)` → `member_status`; `leave_room(p_room_id)`.
- Internal/service: `join_room(p_user_id,p_slug,p_password,p_ip_hash)` → `status,room_id,member_id,display_name` (hanya `service_role`); `record_join_failure(p_slug,p_ip_hash)` (hanya `service_role`, lihat REQUEST); fungsi cron internal tanpa grant client.
- Catatan implementasi: `list_messages` tanpa argumen mengembalikan **50 pesan terakhir** (urut naik); `p_before_id` memuat yang lebih lama; `p_after_id` untuk backfill. `send_message` menerima Host (lihat DECISION).
- Agent B: T-20/T-21 sudah tidak terblokir. Wajib memanggil `record_join_failure(p_slug, hashIp(...))` setelah `join_room` melempar `WRONG_PASSWORD`; tanpa itu lockout/cooldown tidak pernah terisi.
- Agent R: T-40..T-43 sudah tidak terblokir. Wajib `unsubscribe` channel `typing:<room_id>` saat status member bukan `APPROVED` (lihat NOTE Realtime).

## 2026-10-24 12:51 — [D] REQUEST T-13 (kontrak: record_join_failure)
- Spec bagian 6 meminta `join_room` mencatat percobaan gagal lalu melempar `WRONG_PASSWORD`. Di PostgreSQL/PostgREST, exception me-rollback seluruh statement, jadi `INSERT` gagal di dalam `join_room` tidak mungkin bertahan. Ini bukan bug yang bisa diperbaiki dengan urutan statement.
- Solusi yang dipakai: `record_join_failure(p_slug text, p_ip_hash text)` service-only (SECURITY DEFINER, `search_path=''`, grant hanya `service_role`). `join_room` tidak lagi mencatat kegagalan; Agent B mencatatnya sebagai statement terpisah setelah menerima `WRONG_PASSWORD`.
- Ini **tambahan kontrak** (nama RPC baru), bukan perubahan RPC yang sudah ada. Mohon konfirmasi manusia. Jika ditolak, alternatifnya B melakukan `INSERT` langsung ke `public.join_attempts` dengan `service_role` (grant INSERT sudah ada), tetapi itu melanggar preferensi “semua tulis lewat RPC”.
- Uji: `record_join_failure` dipanggil 5x di `200_guest_rpc.test.sql`, percobaan ke-6 menghasilkan `LOCKED`; katalog memastikan `authenticated` tidak punya EXECUTE dan `service_role` punya.

## 2026-10-24 12:52 — [D] DECISION T-13 (Host boleh send_message)
- Tidak ada RPC khusus Host untuk mengirim pesan di kontrak. `send_message` sekarang menerima Host pemilik room: `sender_type='HOST'`, `sender_name='Host'`, tanpa membuat baris member. Guest tetap harus `APPROVED`.
- Kontrak Guest/member tidak berubah untuk client Guest; ini penambahan jalur untuk Host. Sudah diuji di `200_guest_rpc.test.sql`.
- Jika manusia ingin Host memakai RPC terpisah, beri tahu B/F sebelum T-53.

## 2026-10-24 12:53 — [D] NOTE T-15 (hasil uji Realtime private channel)
- Diuji empiris dengan `@supabase/supabase-js` + Supabase lokal: Host dan Guest join channel private `typing:<room_id>`; Guest mengirim Broadcast, Host menerima. Setelah Guest di-`kick_member` (status `KICKED`), channel Guest yang sudah terbuka **tetap bisa mengirim dan menerima** Broadcast (`send` = `ok`, Host tetap menerima). Percobaan join channel baru oleh user yang sama berakhir `TIMEOUT` (tidak `SUBSCRIBED`).
- Artinya otorisasi `realtime.messages` hanya dievaluasi saat join; pencabutan akses tidak memutus channel lama. Ini sesuai keterbatasan yang sudah dicatat di TASK bagian 8.
- Dampak: member `KICKED`/`IDLE`/`LEFT` masih bisa mengirim/menerima denyut “mengetik” sampai reconnect. Payload hanya `{s}` tanpa identitas/konten. Mitigasi wajib di client: begitu status dari `room_members`/heartbeat bukan `APPROVED`, `unsubscribe` channel dan jangan kirim lagi. Tugas R T-42/T-43.
- Tidak ada perubahan SQL yang diperlukan; policy `can_use_typing` sudah menolak join baru setelah status berubah.

## 2026-10-24 12:54 — [D] NOTE T-15 (seed auth)
- Seed mengisi kolom token GoTrue (`confirmation_token`, `recovery_token`, `email_change_token_new`, `email_change`) dengan string kosong. Tanpa itu, login Host lewat `/token` gagal `converting NULL to string is unsupported`.
- Jangan pakai seed ini di produksi. `SUPABASE_SERVICE_ROLE_KEY`, `TURNSTILE_SECRET_KEY`, `IP_HASH_SALT` tidak ada di repo.

## 2026-10-24 12:55 — [D] NOTE T-14 (channel publik)
- Policy `realtime.messages` hanya menjaga channel **private**. Channel publik tidak memakai RLS. Di Supabase lokal `supabase/config.toml` tidak ada toggle “public channels off”; di hosted, cek pengaturan Realtime dan matikan akses channel publik bila tersedia (TASK bagian 5). Client R wajib memakai `{ config: { private: true } }` untuk `typing:<room_id>`.
- Ini item deployment/checklist untuk L/H, bukan sesuatu yang bisa dipaksa dari migration SQL.

## 2026-10-24 13:55 — [D] NOTE docs deploy
- `docs/deploy.md` ditambahkan atas permintaan manusia: runbook deploy Vercel + Supabase + Turnstile + DNS, verifikasi migration/RLS/cron, smoke test, monitoring, backup/rollback, dan daftar blocker.
- Tidak ada perubahan kontrak RPC, kode, atau migration. `docs/setup.md` (zona L) tidak diubah; L dapat menautkan `docs/deploy.md` saat T-70/T-71.
- Status yang dicatat di runbook: `POST /api/rooms/join` masih 501 (T-21), UI belum (T-31/T-52), audit keamanan belum (T-60…T-64), keputusan T-72 belum.
- Catatan operasional penting: free plan Supabase tidak punya backup otomatis; `/api/health?db=1` tetap HTTP 200 saat DB error sehingga keepalive `curl -f` saja belum cukup.

## 2026-10-28 16:44 — [L] HANDOFF T-01
- Dibuat: `eslint.config.mjs` (flat config: `@eslint/js` recommended + `typescript-eslint` recommended + `eslint-plugin-astro` recommended, `eslint-config-prettier/flat` paling akhir), `.prettierrc.mjs` (`singleQuote`, `printWidth: 100`, plugin/parser Astro), `.prettierignore`. Skrip baru di `package.json`: `lint`, `lint:fix`, `format`, `format:check` (skrip lama tidak diubah). CI `.github/workflows/ci.yml` menjalankan `npm run lint` setelah `npm ci` dan sebelum `npm test`.
- Dependency baru (devDependencies): `eslint@^10.13.0`, `@eslint/js@^10.0.1`, `typescript-eslint@^8.72.1`, `eslint-plugin-astro@^3.2.1`, `eslint-config-prettier@^10.1.8`, `globals@^17.13.0`, `prettier@^3.9.10`, `prettier-plugin-astro@^1.1.2`. `package-lock.json` diperbarui lewat `npm install -D`, bukan edit manual.
- Konfigurasi: ignores `dist/.astro/.vercel/node_modules/supabase/design/public/docs`; globals Node+browser untuk JS/TS/Astro; `no-undef` dimatikan hanya untuk TS/Astro; `@typescript-eslint/triple-slash-reference` dimatikan hanya untuk `**/*.d.ts` (`src/env.d.ts`); tanpa typed linting (`projectService`) agar lint cepat.
- Override khusus `src/pages/api/rooms/join.ts`: `no-useless-assignment` dimatikan karena `let turnstileOk = false` selalu ditimpa di `try/catch` (temuan asli, bukan false positive). File milik Agent B; sebaiknya B mengubahnya menjadi `let turnstileOk: boolean;` lalu override di `eslint.config.mjs` dicabut. Tidak ada file `src/**` yang diubah dari zona L.
- Verifikasi (2026-10-28): `npm run lint` bersih — 20 file dilint, 5 di antaranya `.astro`, 0 error/0 warning. `npm test` 20/20 lolos. `npm run check` 0 error/0 warning/0 hint. `npm run build` lolos (hanya peringatan Node lokal 26 vs runtime Vercel 24; tidak fatal). `grep -r SERVICE_ROLE dist/client` kosong.
- `npm run format:check` **belum** dijadikan gate CI: 13 file belum Prettier-clean — `AGENTS.md`, `TASK.md`, `README.md`, `astro.config.mjs`, dan 9 file `src/**` milik B/F/R. Jangan jalankan `npm run format` massal tanpa koordinasi karena akan menyentuh zona peran lain.
- `npm audit`: 7 high, semuanya transitive `@astrojs/vercel` (`path-to-regexp`, `zod` di `@vercel/cli-config`), build-time. Jangan `npm audit fix --force`.
- Cara tes: `npm ci && npm run lint`; coba juga `npx eslint src/pages/index.astro` (harus 0 masalah). `npm run format:check` diharapkan masih gagal sampai file di atas dirapikan pemiliknya.

## 2026-10-28 16:44 — [B] HANDOFF T-20/T-21
- `src/lib/supabase/server.ts`: validasi env, `getAnonClient()`, `verifyAccessToken()` menolak token kosong, dan tipe `JoinRoomRow`.
- `src/pages/api/rooms/join.ts`: implementasi penuh kontrak TASK.md bagian 7 — zod → Turnstile → Bearer token → `hashIp(clientAddress)` → RPC `join_room` (service_role) → pemetaan error. `WRONG_PASSWORD` memanggil `record_join_failure` di statement terpisah; `LOCKED`/`ROOM_COOLDOWN` mengirim `Retry-After`.
- `src/lib/server/join-errors.ts` + `join-errors.test.ts`: pemetaan kode RPC ke HTTP (401/429/403/404/400/500) dan parsing `retry_after`.
- **Turnstile ditunda atas permintaan manusia.** Di `astro dev`, bila `TURNSTILE_SECRET_KEY` kosong, verifikasi dilewati. Build produksi (`import.meta.env.DEV === false`) tetap **wajib** punya secret; kalau kosong endpoint mengembalikan 500, bukan membuka akses. Jangan deploy tanpa secret Turnstile asli.
- `.env.local` dibuat untuk Supabase lokal (URL `http://127.0.0.1:54321`, kunci `sb_publishable_`/`sb_secret_`). `.env` milik manusia tetap menunjuk project hosted, tetapi schema project itu masih kosong (`tier_limits` 404) dan akun CLI yang login sekarang tidak punya akses ke project tersebut (`LinkProjectStatusError`). Project hosted perlu di-link/di-push dari akun pemiliknya sebelum dipakai.
- Verifikasi: `npm test` 20/20; `npm run check` 0 error; `npm run build` lolos (env lokal); `grep` `dist/client` bersih; `supabase test db` 123 PASS; `supabase db reset` sukses.
- Uji manual lokal via `POST /api/rooms/join` + anonymous user: sukses 200 `APPROVED`; password salah 401 `WRONG_PASSWORD` dan `join_attempts` bertambah; 5 kegagalan → 429 `LOCKED` + `Retry-After`; slug tidak ada 404; body invalid 400; tanpa token/invalid token 401.
- Status MVP: backend join siap. Sisa utama: UI T-31/T-50–T-53, realtime T-40–T-43, CSP T-22, audit T-60–T-64. Turnstile asli baru dipasang di tahap deploy (T-70).

## 2026-10-28 16:47 — [B] NOTE T-21 (smoke backend MVP)
- Smoke end-to-end dengan Supabase lokal + endpoint join berhasil: Host `dev@example.com` login → `create_room` → Guest anonymous sign-in → `POST /api/rooms/join` (200 `APPROVED`, `Guest-01`) → Guest `send_message` → Host `send_message` → Host `list_messages` (2 pesan, sender `GUEST` lalu `HOST`).
- Setelah smoke, `supabase db reset` dijalankan lagi agar data uji (room/pesan/member) hilang dan seed dev bersih.
- Ini memverifikasi jalur backend MVP; UI dan Realtime belum.

## 2026-10-28 16:52 — [L] REQUEST T-01 (override sementara)
- `src/pages/api/rooms/join.ts` memicu `no-useless-assignment` (ESLint 10) karena `let turnstileOk = false` selalu ditimpa di `try`/`catch`. Ini temuan asli, bukan false positive.
- Karena file milik Agent B, zona L tidak mengubahnya. Sementara `eslint.config.mjs` mematikan rule itu khusus file tersebut.
- Mohon B mengganti menjadi `let turnstileOk: boolean;` (definite assignment tetap aman: `try` mengisi hasil, `catch` mengisi `false`), lalu L/ B mencabut override di `eslint.config.mjs`. Tidak ada perubahan kontrak.

## 2026-10-28 16:52 — [L] NOTE T-01 (status Prettier)
- `README.md` dan `astro.config.mjs` sudah diformat dengan Prettier. `AGENTS.md`, `TASK.md`, `TODO.md`, `docs/`, `design/`, `public/`, `supabase/` dikecualikan lewat `.prettierignore`.
- `npm run format:check` sekarang hanya menandai file `src/**` milik B/F/R yang belum diformat. Setiap pemilik zona dapat menjalankan `npx prettier --write <file>`; setelah bersih, gate `format:check` bisa ditambahkan ke CI.

## 2026-10-28 16:53 — [L] NOTE T-01 (verifikasi akhir)
- Verifikasi ulang setelah pekerjaan F/B berjalan: `npm run lint` bersih dengan `--max-warnings=0` (0 error/0 warning), `npm test` 20/20, `npm run check` 29 file 0 error/0 warning/0 hint, `npm run build` lolos (hanya peringatan Node lokal 26 vs runtime Vercel 24), `grep -r SERVICE_ROLE dist/client` kosong.
- Angka "20 file dilint, 5 .astro" di HANDOFF T-01 adalah snapshot saat entri itu ditulis; jumlah file bertambah karena F menambah komponen/halaman.
- `npm run format:check` masih menandai 18 file `src/**` milik B/F/R; belum dijadikan gate CI.

## 2026-10-29 09:50 — [F] HANDOFF T-31 (UI statis, tema Stiker bawaan)
- T-31 selesai: kerangka UI statis penuh dengan data tiruan. T-30 boleh selesai setelah ekspor Figma manusia (tokens.css sekarang sudah berisi DNA Stiker bawaan atas arah manusia, bukan placeholder).
- **Keputusan manusia yang bekerja:** tema = template **Stiker BAWAAN** situs utama (`umpomenfess/src/styles/templates.css` `.tpl-stiker`; mint #DFF2EC→#BFE5DA), bukan kaca-blush (sudah dipakai subsite form).
- **File baru:** `design/tokens.css` (ditulis ulang; kontras dihitung, pasangan ≥4.5 — catat di `design/README.md`), `design/base.css`, `design/chat.css`, `design/README.md`, `src/components/{SiteHeader,SiteFooter,StickerDecor}.astro`, `src/components/mockData.ts`. **File diubah:** `src/layouts/Base.astro` (skip-link, font Baloo 2+Quicksand+Space Mono, favicon, meta, chrome compact), halaman: `/` `/login` `/register` `/dashboard` `/dashboard/r/[id]` `/r/[slug]` `/rooms` `/privasi` `/batas-anonimitas`.
- **Cara tes:** `npm run check`, `npm test` (20), build dengan env publik inline (tanpa `.env`), lalu `npm run dev` dan buka: `/r/<slug>` + query `?state=` salah|kunci|penuh|pending|ditolak|keluar|idle|tutup|maks|chat — semua 10 keadaan bagian 11 + chat + password tersedia sebagai pratinjau statis. Screenshot desktop 1440 & mobile 390 sudah dicek; `grep -rEi "SERVICE_ROLE|TURNSTILE_SECRET|IP_HASH_SALT" dist/client` = 0.
- **Hal yang perlu diketahui agent berikutnya:** (1) halaman statis sengaja tanpa dark mode dan tanpa JS; kontrak interaksi nyata menyusul T-50..T-54. (2) Stiker SVG 1:1 dari `src/lib/templates/render.ts` situs utama — jangan ganti emoji. (3) Astro memangkas whitespace antar elemen: tulis teks lanjutan segaris dengan tag penutup atau buat span `display:block` (lihat fix `.mp__name`). (4) Koral dekorasi `--coral` hanya untuk elemen besar; tombol/teks aksen wajib `--coral-strong` (kontras). (5) T-30 masih menunggu ekspor Figma; tokens.css akan ditimpa nilai Figma bila datang. (6) zona F dihormati — tidak ada file di luar `src/pages`, `src/layouts`, `src/components`, `design/`.
- **Verifikasi keamanan ringan:** halaman chat/panel member menampilkan Guest sebagai nomor (Guest-01 dst) tanpa kolom identitas — konsisten D-05/S-09.
