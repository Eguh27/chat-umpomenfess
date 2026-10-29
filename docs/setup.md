# Setup manual (dikerjakan manusia)

Langkah yang butuh akun. Agent L hanya memeriksa, tidak membuatnya.

## 1. Supabase (akun/proyek BARU, terpisah dari menfess dan form)
- [ ] Buat akun/proyek baru. Catat `Project URL`, `anon key`, `service_role key`.
- [ ] Authentication → aktifkan **Anonymous Sign-Ins**.
- [ ] Authentication → Attack Protection → aktifkan **CAPTCHA (Turnstile)** dengan secret key Turnstile.
- [ ] Authentication → URL Configuration: Site URL = subdomain final; tambah redirect URL untuk dev (`http://localhost:4321`).
- [ ] Putuskan konfirmasi email Host (TASK.md bagian 14). SMTP bawaan Supabase terbatas jumlah emailnya.
- [ ] Database → Extensions: `pgcrypto`, `pg_cron` aktif (migration T-10 yang mengaktifkan; verifikasi hasilnya).
- [ ] Realtime → Settings: matikan akses channel **publik** (jika tersedia) agar channel wajib private.
- [ ] Jalankan migration: `supabase link --project-ref <ref>` lalu `supabase db push`.

## 2. Cloudflare Turnstile
- [ ] Buat widget untuk hostname subdomain final (+ `localhost` untuk dev). Simpan site key dan secret key.

## 3. Vercel
- [ ] Import repo baru sebagai project baru (project kedua/ketiga; Hobby).
- [ ] Settings → Node.js version: **22.x** (Astro 7 butuh Node ≥ 22.22).
- [ ] Environment Variables: lihat `.env.example` (rahasia **tanpa** awalan `PUBLIC_`).
- [ ] Domains: tambah subdomain, catat nilai CNAME yang diminta Vercel.
- [ ] Firewall → buat 1 rule rate limit pada `POST /api/rooms/join` (Hobby hanya 1 rule rate limit).

## 4. DNS (Cloudflare, domain milik sendiri)
- [ ] Tambah `CNAME <subdomain>` → nilai dari Vercel, **Proxy status: DNS only (awan abu-abu)**.

## 5. GitHub
- [ ] Secret `SITE_URL` (mis. `https://<subdomain>`) untuk workflow keep-alive.
- [ ] Catatan: GitHub menonaktifkan workflow terjadwal di repo **publik** yang tidak ada aktivitas 60 hari. Jalankan manual (`workflow_dispatch`) bila perlu, atau gunakan repo privat.

## 6. Pemantauan setelah rilis (T-71)
- [ ] Supabase → Usage: Realtime messages (kuota free 2 juta/bulan), koneksi puncak (±200), ukuran DB (500 MB).
- [ ] Pastikan proyek tidak ter-pause: workflow keep-alive berjalan (Senin & Kamis).
- [ ] `select * from cron.job_run_details order by start_time desc limit 20;` — job berjalan tanpa error.

## Catatan teknis
- `npm audit` menampilkan 3 temuan "high" dari `path-to-regexp` lewat `@astrojs/vercel` (dependensi build-time). **Jangan** `npm audit fix --force` (menurunkan adapter ke versi lama). Pantau rilis adapter.
- Setelah build: `grep -r "SERVICE_ROLE\|TURNSTILE_SECRET\|IP_HASH_SALT" dist/client .vercel/output/static` harus kosong.
