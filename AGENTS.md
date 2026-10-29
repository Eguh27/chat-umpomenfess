# AGENTS.md — Aturan permanen (umpomenfess-room)

Project 3 dari ekosistem UMPOMENFESS: **room chat anonim** di subdomain sendiri.
Repo, project Vercel, dan project Supabase TERPISAH dari situs menfess utama dan project form.
Spesifikasi lengkap ada di `TASK.md`. Papan tugas ada di `TODO.md`. Log serah-terima di `docs/progress.md`.

## 1. Keputusan terkunci (jangan diubah tanpa persetujuan manusia)

- Astro SSR + adapter Vercel + React island. Backend = Supabase (Postgres, Auth, Realtime, RLS).
- **Tidak ada Socket.io / server WebSocket sendiri.** Vercel itu serverless.
- Cloudflare hanya **DNS-only** (tanpa proxy). Turnstile tetap dipakai.
- Guest = Supabase **Anonymous Sign-in**. Host = email/password (Supabase Auth).
- **Semua tulis ke database lewat RPC.** Tidak ada policy INSERT/UPDATE/DELETE untuk `anon`/`authenticated` di tabel inti.
- **Host tidak pernah bisa melihat `user_id` Guest** (tabel identitas dipisah, lihat TASK.md bagian 4).
- Konten pesan dirender sebagai **teks biasa**. Tidak ada `set:html` / `dangerouslySetInnerHTML` untuk data user.
- Pembayaran belum ada. `tier` diubah manual (SQL / service_role).
- Indikator mengetik = Realtime Broadcast **agregat tanpa identitas** (TASK.md bagian 8).

## 2. Peran dan zona tulis

Satu agent = satu peran. Hanya menulis di zonanya. Perlu mengubah file di luar zona → tulis `REQUEST` di `docs/progress.md`, jangan edit sendiri.

| Peran | Nama | Zona tulis |
|---|---|---|
| **L** | Lead / setup / ops | `package.json`, `astro.config.mjs`, `tsconfig.json`, `vercel.json`, `.github/**`, `scripts/*` (kecuali `scripts/security/`), `README.md`, `docs/setup.md` |
| **D** | Database | `supabase/**` (kecuali `supabase/tests/security/`) |
| **B** | Backend / API server | `src/pages/api/**`, `src/lib/server/**`, `src/lib/supabase/server.ts`, `src/lib/ip.ts`, `src/lib/schemas.ts` |
| **R** | Realtime client | `src/lib/realtime/**`, `src/lib/supabase/browser.ts`, `src/lib/config.ts` |
| **F** | Frontend / UI | `src/pages/*.astro`, `src/pages/r/**`, `src/layouts/**`, `src/components/**`, `design/**`, `public/*` (kecuali `robots.txt`) |
| **S** | Security / QA | `scripts/security/**`, `supabase/tests/security/**`, `docs/audit/**` (read-only di tempat lain) |

Bersama: `TASK.md` dan `AGENTS.md` hanya diubah manusia (atau L dengan persetujuan manusia). `TODO.md`: ubah hanya baris tugasmu. `docs/progress.md`: **append-only**.

## 3. Alur kerja

1. Baca `AGENTS.md` → bagian relevan `TASK.md` → `TODO.md`.
2. Klaim tugas: ubah `[ ]` menjadi `[~] @PERAN` sebelum mulai. Jangan ambil tugas yang `depends` belum `[x]`.
3. Kerjakan di zonamu. Jalankan perintah verifikasi yang tertulis di tugas.
4. Selesai: ubah ke `[x]`, lalu tambah entri `HANDOFF` di `docs/progress.md` (apa yang dibuat, file, cara tes, hal yang perlu diketahui agent berikutnya).
5. **Kontrak berubah** (nama RPC, kolom, payload, kode error)? Berhenti. Tulis `REQUEST` dan tunggu manusia. Jangan mengubah kontrak sepihak.
6. Paralel hanya untuk tugas yang independen (lihat Wave di `TODO.md`).
7. Mode: **Plan** untuk audit/review, **Build** untuk eksekusi.
8. Commit kecil: `T-xx: ringkasan singkat`.

## 4. Aturan keamanan (tidak bisa ditawar)

- `SUPABASE_SERVICE_ROLE_KEY`, `TURNSTILE_SECRET_KEY`, `IP_HASH_SALT` hanya di kode server dan env Vercel. **Jangan pernah** berawalan `PUBLIC_`, jangan di-import dari kode client. Setelah build: `grep -r SERVICE_ROLE dist/client` harus kosong.
- IP mentah tidak boleh disimpan atau di-log. Simpan hanya `hashIp()` (HMAC, IPv6 → /64).
- Isi pesan dan password tidak boleh masuk log (server, Vercel, atau DB).
- Setiap fungsi SQL: `SECURITY DEFINER` hanya bila perlu, selalu `SET search_path = ''` dengan nama tabel ber-schema, lalu `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` dan `GRANT` eksplisit ke role yang berhak. (Postgres memberi EXECUTE ke PUBLIC secara default.)
- Identitas selalu dari `auth.uid()` di dalam fungsi. Jangan percaya parameter `user_id`, `sender_name`, atau `sender_type` dari client.
- Pengguna anonim juga berperan `authenticated`. RPC khusus Host **wajib** menolak JWT anonim (`is_anonymous`).
- RLS aktif di semua tabel `public`, termasuk tabel yang "tidak diakses client".
- Jangan menambah dependency tanpa catatan di `docs/progress.md`. Jangan `npm audit fix --force`.
- Jangan commit `.env`.

## 5. Konvensi

- TypeScript strict, validasi input dengan `zod`, tanpa `any`.
- Teks UI: Bahasa Indonesia santai tapi sopan. Identifier, nama RPC, kode error: Inggris.
- Migration SQL: bernomor berurutan (`0001_...sql`), satu topik per file, aman dijalankan ulang di database lokal (`supabase db reset`).
- Kode error RPC: `RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='<KODE>'`. Daftar kode ada di `TASK.md` bagian 6.
- Komentar kode boleh Indonesia.

## 6. Perintah

```bash
npm run dev          # dev server
npm test             # vitest
npm run check        # astro check (tipe)
npm run build        # build (butuh env PUBLIC_* terisi)
supabase start       # Postgres + Realtime lokal (Docker)
supabase db reset    # jalankan semua migration + seed
supabase test db     # jalankan tes SQL (pgTAP)
```

## 7. Definition of done (per tugas)

- Perintah verifikasi di tugas lolos.
- `npm test`, `npm run check`, `npm run build` lolos (untuk tugas yang menyentuh `src/`).
- Tidak ada perubahan di luar zona tulis.
- Entri `HANDOFF` sudah ditulis.

## 8. Panduan model (opencode)

Model gratis sering berganti, cek `/models`. Model terkuat untuk **D** dan **S** (RLS, RPC, review keamanan). Model menengah-kuat untuk **B** dan **R**. Model ringan cukup untuk **F** dan **L**.
