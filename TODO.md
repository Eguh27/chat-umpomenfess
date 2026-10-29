# TODO.md — Papan tugas

Legenda: `[ ]` belum · `[~] @PERAN` dikerjakan · `[x]` selesai · `[!]` terblokir (tulis alasan di `docs/progress.md`).
Peran: **L** lead/ops · **D** database · **B** backend/API · **R** realtime client · **F** frontend · **S** security/QA · **H** manusia.
Format: `ID [Peran] judul — depends — verifikasi`. Spesifikasi detail: `TASK.md` (nomor bagian di kurung).

## Wave 0 — Fondasi

- [x] T-00 [L] Kerangka project: Astro 7 + Vercel + React, `astro:env`, helper `ip.ts` + tes, header keamanan, workflow CI & keep-alive — verifikasi: `npm test`, `npm run check`, `npm run build` lolos (sudah diverifikasi saat zip dibuat)
- [x] T-01 [L] Tambah ESLint + Prettier minimal dan skrip `npm run lint`; perbarui CI — depends T-00 — verifikasi: `npm run lint` bersih
- [ ] H-01 [H] Siapkan akun/proyek Supabase BARU, Turnstile, proyek Vercel, DNS (lihat `docs/setup.md`) — paralel dengan semua wave awal

## Wave 1 — Database dan UI statis (paralel, independen)

- [x] T-10 [D] Migration 0001: ekstensi (`pgcrypto`, `pg_cron`), enum `member_status`, semua tabel, constraint, index, seed `tier_limits` + `app_config` (bagian 3, 4) — depends T-00 — verifikasi: `supabase db reset` sukses
- [x] T-11 [D] Migration 0002: schema `app_private` + fungsi pembantu, `REVOKE`/default privileges, RLS + policy, grant kolom `rooms`, publication Realtime, trigger `profiles` (bagian 5) — depends T-10 — verifikasi: `supabase db reset` + query katalog S-15
- [x] T-12 [D] Migration 0003: RPC Host (`create_room` … `export_messages`) (bagian 6) — depends T-11 — verifikasi: tes pgTAP per RPC di `supabase/tests/`
- [x] T-13 [D] Migration 0004: RPC Guest + `join_room` (service-only) + penomoran atomik + `release_idle_members` (bagian 6, 8) — depends T-12 — verifikasi: tes pgTAP: lockout, kursi penuh, idle release, rejoin
- [x] T-14 [D] Migration 0005: job `pg_cron` + kebijakan `realtime.messages` untuk `typing:<room_id>` (bagian 5, 9) — depends T-13 — verifikasi: `cron.job` berisi 4 job; tes policy
- [x] T-15 [D] Tes SQL lengkap + `supabase/seed.sql` dev; **cek perilaku otorisasi Realtime private channel setelah member dikeluarkan** dan catat hasilnya di progress.md — depends T-14 — verifikasi: `supabase test db` hijau
- [~] T-30 [F] Terapkan token Figma ke `design/tokens.css` (menunggu ekspor dari manusia; sementara sudah terisi DNA **Stiker bawaan** atas arah manusia 2026-10-28, bukan placeholder kosong lagi) — depends H (token) — verifikasi: halaman memakai variabel CSS, tanpa warna hard-coded
- [x] T-31 [F 2026-10-28] Kerangka UI statis dengan data tiruan: landing, login/register, dasbor, form buat room, tampilan chat, panel member, halaman Ruang saya, disclaimer — depends T-00 — verifikasi: `npm run build`; semua keadaan Guest di bagian 11 punya tampilan (tema Stiker bawaan; keadaan Guest bisa dipratinjau lewat `?state=…`)

## Wave 2 — Integrasi server dan realtime (paralel setelah kontrak RPC stabil)

- [x] T-20 [B] Rapikan `lib/supabase/server.ts`, validasi env, tipe hasil RPC (selaras kontrak bagian 6) — depends T-13 — verifikasi: `npm run check`
- [x] T-21 [B] Implementasi `POST /api/rooms/join` penuh (bagian 7) + tes unit pemetaan error (mock) — depends T-13, T-20 — verifikasi: `npm test`; uji manual dengan Supabase lokal
- [ ] T-22 [B] CSP + header tambahan (izinkan `*.supabase.co` https/wss, `challenges.cloudflare.com`), uji tidak merusak Turnstile/Realtime — depends T-31 — verifikasi: tidak ada pelanggaran CSP di konsol; S-18
- [~] @R T-40 [R] Modul realtime: subscribe pesan + status member, backfill saat reconnect, dedupe, kirim optimistis (bagian 8) — depends T-13 — verifikasi: tes unit dengan client tiruan
- [ ] T-41 [R] Paginasi riwayat (50 awal, memuat ke atas) dan ekspor `.txt` WIB — depends T-40 — verifikasi: tes unit format baris ekspor
- [ ] T-42 [R] Heartbeat `touch_activity` (visibility-aware) + penanganan status `IDLE`/`KICKED`/`LEFT` + `rejoin_room` — depends T-40 — verifikasi: tes unit penjadwalan (fake timers)
- [ ] T-43 [R] Indikator mengetik (Broadcast private agregat, throttle 5 dtk, kedaluwarsa 6 dtk, hormati `typing_effective`) — depends T-14, T-40 — verifikasi: tes unit throttle + agregasi

## Wave 3 — UI terhubung

- [ ] T-50 [F] Auth Host (register/login/logout) + Turnstile + penanganan konfirmasi email — depends T-31, T-20 — verifikasi: alur manual end-to-end
- [ ] T-51 [F] Dasbor Host: daftar room, sisa waktu, kuota, form buat room (kapasitas ≤ cap tier), tampilkan password sekali, regenerate, tutup — depends T-50, T-12 — verifikasi: manual; kuota habis menampilkan pesan yang benar
- [~] T-52 [@F 2026-10-29] Halaman Guest `/r/<slug>`: disclaimer → Turnstile → sign-in anonim → `POST /api/rooms/join` → semua keadaan bagian 11 — depends T-21, T-31 — verifikasi: manual tiap keadaan (island JoinRoom nyata; pratinjau statis `?state=` dipertahankan)
- [ ] T-53 [F] Ruang chat Host & Guest + panel member (Approve/Reject/Kick) + countdown + tampilan mengetik/idle — depends T-40, T-41, T-42, T-43, T-52 — verifikasi: dua browser berbeda
- [ ] T-54 [F] Halaman `/rooms` (Ruang saya) + penanda belum dibaca di `localStorage` + peringatan batasan penyimpanan — depends T-53 — verifikasi: ikut di 2 room sekaligus, state bertahan setelah refresh
- [~] T-55 [@F 2026-10-29] Halaman `/privasi` dan `/batas-anonimitas` (bahasa Indonesia, jujur soal log infrastruktur dan akses admin database) — depends T-31 — verifikasi: ditinjau manusia (draft dirapatkan; menunggu tinjauan manusia)

## Wave 4 — Audit keamanan (mode Plan dulu, lalu Build untuk skrip)

- [~] @S T-60 [S] Audit RLS/RPC/grant terhadap bagian 5–6 (Plan). Keluaran: `docs/audit/rls-audit.md` — depends T-15 — verifikasi: setiap temuan punya ID dan tingkat keparahan
- [ ] T-61 [S] Skrip serangan S-01…S-14, S-19, S-20 di `scripts/security/` (REST + RPC langsung) — depends T-15 — verifikasi: semua menghasilkan hasil yang benar; dapat dijalankan ulang
- [ ] T-62 [S] S-15 (katalog), S-16 (grep bundle), S-17 (XSS), S-18 (header/CSP) — depends T-22, T-53 — verifikasi: skrip hijau
- [ ] T-63 [S] Uji beban ringan: 40 klien simulasi dalam satu room; catat koneksi dan hitungan pesan Realtime; bandingkan dengan kuota free — depends T-53 — verifikasi: laporan di `docs/audit/load.md`
- [ ] T-64 [D/B/R/F] Perbaiki temuan T-60…T-63 (masing-masing peran di zonanya) — depends T-60 — verifikasi: S menjalankan ulang semua skrip

## Wave 5 — Rilis

- [ ] T-70 [L] Deploy: env Vercel, Node 22, domain/CNAME DNS-only, konfigurasi Supabase (anonymous sign-in, CAPTCHA, URL redirect, `pg_cron` aktif), rule WAF join, secret GitHub (`SITE_URL`) — depends T-64, H-01 — verifikasi: daftar periksa `docs/setup.md` tercentang
- [ ] T-71 [L] Daftar periksa monitoring: usage Realtime, koneksi, ukuran DB, jalankan manual keep-alive, cek `cron.job_run_details` — depends T-70 — verifikasi: ditulis di `docs/setup.md`
- [ ] T-72 [H] Putuskan pertanyaan terbuka (TASK.md bagian 14) dan konfirmasi angka kuota — sebelum T-70

## Catatan paralelisme

- Wave 1: D dan F jalan bersamaan (tidak saling bergantung).
- Wave 2: B dan R jalan bersamaan setelah T-13 selesai. Hindari mulai sebelum kontrak RPC dibekukan.
- Wave 3 bergantung pada Wave 2. Satu agent F saja untuk menghindari konflik file.
- Wave 4: S tidak boleh mengedit kode di luar zonanya; perbaikan dikembalikan ke pemilik zona lewat T-64.
