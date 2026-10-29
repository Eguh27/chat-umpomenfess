# Deploy MVP — umpomenfess-room

Runbook operasional untuk mendeploy project ini ke **Vercel + Supabase + Cloudflare Turnstile/DNS**.
Dokumen ini melengkapi checklist manual di `docs/setup.md`; `docs/setup.md` tetap dipakai sebagai daftar centang T-70/T-71.

Terakhir disusun: **24 Oktober 2026**. Angka kuota free plan dan label dasbor bisa berubah — verifikasi ulang sebelum rilis.

---

## 0. Status kesiapan (baca dulu)

| Bagian | Status | Catatan |
|---|---|---|
| Database, RLS, RPC, cron | **Siap** | T-10…T-15 selesai; 123 tes pgTAP lolos. |
| `POST /api/rooms/join` | **Belum** | Masih stub `501 NOT_IMPLEMENTED` sampai T-21. |
| UI Guest/Host | **Belum** | Masih kerangka/placeholder sampai T-31, T-50…T-53. |
| Audit keamanan | **Belum** | T-60…T-64 belum dijalankan. |
| Pertanyaan terbuka | **Belum diputuskan** | T-72 (TASK.md bagian 14). |

Artinya:

- **Sekarang** panduan ini bisa dipakai untuk deploy **staging/preview**: menyiapkan Supabase, migration, Vercel, domain, dan monitoring.
- **Jangan umumkan sebagai layanan publik** sebelum T-21 (join), T-52 (UI Guest), T-64 (perbaikan temuan), dan T-72 (keputusan manusia) selesai.
- Deploy Vercel sekarang akan menghasilkan halaman shell dan `/api/health`; join masih 501. Itu normal, bukan kegagalan deploy.

### Alur singkat

1. Buat project Supabase + atur Auth/Realtime + catat kunci.
2. Buat widget Turnstile (production + localhost).
3. `supabase link` → `db push --dry-run` → `db push` → verifikasi SQL.
4. Import repo ke Vercel + env + domain + rate limit join.
5. Tambah CNAME Cloudflare (**DNS only**).
6. Set secret `SITE_URL` + uji keepalive.
7. Smoke test, monitoring, dan backup manual.

---

## 1. Prasyarat

- Node.js **22.22+** (sesuai `package.json`). Jangan memakai Node 26 untuk build produksi jika belum diuji.
- npm dan `package-lock.json` sudah ada.
- Akun Supabase, Vercel, Cloudflare, dan GitHub.
- Domain yang dikelola di Cloudflare (DNS-only, bukan proxy).
- Docker (untuk `supabase start`, `supabase test db`, dan `db dump`).
- Supabase CLI. Semua contoh memakai:
  ```bash
  npx --yes supabase@latest <perintah>
  ```
  Jika CLI global sudah terpasang, `supabase <perintah>` juga boleh.

### 1.1 Cek lokal sebelum menyentuh produksi

```bash
npm ci
cp .env.example .env       # isi PUBLIC_* lokal; jangan commit
npm test
npm run check
npm run build

npx --yes supabase@latest start
npx --yes supabase@latest db reset
npx --yes supabase@latest test db
```

Yang harus hijau:

- `npm test` — 20/20.
- `npm run check` — 0 error.
- `npm run build` — sukses (butuh `PUBLIC_*`; lihat `.env.example`).
- `supabase test db` — 123 tes pgTAP PASS.
- `supabase db reset` — semua migration + seed lokal sukses.

Untuk MVP lokal, `.env.local` (gitignored) boleh menimpa `.env` dan menunjuk Supabase lokal (`http://127.0.0.1:54321`) dengan kunci dari `supabase status`. Di `astro dev`, verifikasi Turnstile dilewati **hanya bila** `TURNSTILE_SECRET_KEY` kosong; `astro build`/produksi tetap mewajibkan secret Turnstile asli. Jangan mengandalkan bypass ini saat deploy.

### 1.2 Siapkan repository Git

Direktori ini **belum berupa repo Git**. Vercel membutuhkan repo Git (GitHub/GitLab/Bitbucket).

```bash
git init
git add .
git commit -m "chore: MVP database and app shell"
git branch -M main
git remote add origin git@github.com:<akun>/<repo>.git
git push -u origin main
```

Sebelum commit:

```bash
git status --short          # pastikan .env tidak ikut
git check-ignore .env       # harus menghasilkan .env
```

Repo **private** disarankan: workflow terjadwal GitHub bisa dinonaktifkan di repo publik yang tidak ada aktivitas 60 hari, dan kode ini belum diaudit.

---

## 2. Supabase — project baru

Project ini **terpisah** dari situs menfess utama dan project form. Jangan memakai project yang sama.

1. Buka <https://supabase.com/dashboard> → **New project**.
2. Pilih organization, nama project (mis. `umpomenfess-room`), dan region terdekat dengan pengguna (mis. Singapura).
3. Simpan **database password** di password manager. Password ini dipakai `supabase link`/`db push`.
4. Tunggu provisioning selesai.

> **Batas Free plan:** maksimal **2 project aktif per organization**. Jika organization yang sama sudah dipakai untuk menfess utama + project form, buat organization baru atau upgrade ke Pro sebelum membuat project ketiga.

### 2.1 Ambil kunci API

Buka **Project Settings → API Keys**.

Supabase sedang memigrasikan kunci lama ke kunci baru:

| Kebutuhan app | Nama env di project | Kunci baru (disarankan) | Kunci lama |
|---|---|---|---|
| Client/browser | `PUBLIC_SUPABASE_ANON_KEY` | Publishable `sb_publishable_...` | `anon` JWT |
| Server saja | `SUPABASE_SERVICE_ROLE_KEY` | Secret `sb_secret_...` | `service_role` JWT |

- Nama variabel di kode masih memakai istilah lama, tetapi **nilainya boleh kunci baru**; `supabase-js` menerima keduanya.
- Jangan menaruh secret di variabel berawalan `PUBLIC_`.
- Jangan menonaktifkan kunci lama sebelum semua env dan kode diuji dengan kunci baru.
- Kunci `anon`/`service_role` lama akan dipensiunkan akhir 2026. Prioritaskan migrasi ke publishable/secret.

Catat juga **Project URL**: `https://<ref>.supabase.co`.

### 2.2 Authentication

Buka **Authentication**:

- **Providers → Anonymous sign-ins**: aktifkan. Guest memakai anonymous sign-in.
- **Providers → Email**: aktifkan signup Host.
- **Attack Protection → CAPTCHA**: pilih **Turnstile**, tempel **secret key** Turnstile (bagian 3).
- **URL Configuration**:
  - **Site URL**: `https://<subdomain-final>` (tanpa trailing slash).
  - **Redirect URLs**: tambahkan
    - `https://<subdomain-final>/**`
    - `http://localhost:4321/**`
    - pola preview Vercel jika dipakai, mis. `https://*-<team>.vercel.app/**` (jika didukung dasbor).
- **Sessions**: JWT expiry `3600`, refresh token rotation aktif (default).
- **Rate limits**: anonymous sign-ins default 30/jam/IP. Pantau; naikkan hanya jika perlu.
- **Email confirmations**:
  - Default TASK.md bagian 14: **aktif**.
  - Untuk MVP tanpa SMTP, ini membuat Host tidak bisa login sampai email dikonfirmasi.
  - Jika tetap aktif: konfigurasi **custom SMTP** (Resend/SES/Postmark) sebelum rilis. SMTP bawaan Supabase terbatas dan tidak untuk produksi.
  - Jika dimatikan untuk MVP: catat sebagai keputusan manusia dan risiko (email palsu bisa mendaftar).

**Penting:** `supabase db push` hanya mendorong database. Pengaturan Auth, Realtime, dan API di atas **tidak** ikut dari `supabase/config.toml`; atur di dasbor.

### 2.3 Realtime

Buka **Realtime → Settings**:

- Pastikan Realtime **enabled**.
- Matikan **Allow public access to channels** (private-only). Dengan ini, client yang tidak memakai `config: { private: true }` ditolak (`PrivateOnly`).
- Biarkan connection pool default kecuali ada masalah koneksi.

Migration `0005` memasang policy `realtime.messages` untuk topik `typing:<room_id>`. Policy hanya dibuat jika tabel `realtime.messages` sudah ada saat migration berjalan. Karena itu:

1. Aktifkan Realtime **sebelum** `db push`.
2. Setelah `db push`, verifikasi policy (bagian 4.3). Jika kosong, jalankan ulang blok `create policy` dari `0005_cron_realtime.sql` di SQL Editor (blok itu idempotent: `drop policy if exists` lalu `create policy`).

### 2.4 Ekstensi database

Migration `0001` menjalankan:

```sql
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;
```

Di hosted Supabase, `pg_cron` biasanya bisa dibuat dari migration. Jika gagal dengan error permission/extension:

1. Buka **Database → Extensions**.
2. Aktifkan **pg_cron**.
3. Ulangi `supabase db push` (migration yang gagal tidak tercatat di history).

`pgcrypto` biasanya sudah ada. Jangan memindahkan schema extension secara manual.

---

## 3. Cloudflare Turnstile

Turnstile dipakai di dua tempat:

1. **Supabase Auth** — CAPTCHA saat anonymous sign-in dan login/register Host.
2. **Aplikasi** — `POST /api/rooms/join` memverifikasi token sebelum join (T-21).

Keduanya memakai widget dan secret yang sama.

### 3.1 Buat widget

1. Cloudflare Dashboard → **Turnstile** → **Add widget**.
2. Nama: `umpomenfess-room`.
3. Hostnames:
   - `<subdomain-final>` (mis. `room.example.com`)
   - `localhost` (untuk development)
   - hostname preview Vercel jika akan menguji auth di preview.
4. Widget mode: **Managed**.
5. Simpan **Site Key** dan **Secret Key**.

Untuk lokal saja, Cloudflare menyediakan test key yang selalu lolos:

```text
Site key : 1x00000000000000000000AA
Secret   : 1x0000000000000000000000000000000AA
```

Jangan memakai test key di produksi.

### 3.2 Token Turnstile sekali pakai

Token Turnstile:

- hanya berlaku sekali,
- kedaluwarsa sekitar 5 menit,
- terikat pada widget/hostname.

Alur UI yang benar:

1. Guest menyelesaikan widget → token A.
2. Token A dikirim ke Supabase `signInAnonymously({ options: { captchaToken: tokenA } })`.
3. Sebelum `POST /api/rooms/join`, widget di-reset/ulang → token B.
4. Token B dikirim di body join.

Jika token yang sama dipakai dua kali, Cloudflare mengembalikan `timeout-or-duplicate` dan join gagal. Ini bukan bug server.

### 3.3 Simpan secret

- `TURNSTILE_SECRET_KEY` → Vercel (secret) **dan** Supabase Auth CAPTCHA.
- `PUBLIC_TURNSTILE_SITE_KEY` → Vercel (public) dan browser.

Jangan menaruh secret Turnstile di `PUBLIC_*`.

---

## 4. Dorong migration ke Supabase hosted

### 4.1 Backup dulu

Untuk project baru yang masih kosong, backup tidak wajib. Untuk project yang sudah berisi data:

```bash
npx --yes supabase@latest db dump --linked -f backup-schema.sql
npx --yes supabase@latest db dump --linked --data-only -f backup-data.sql
```

`db dump` membutuhkan Docker dan tidak menyertakan schema `auth`/`storage`. **Free plan tidak punya backup otomatis**; dump manual adalah satu-satunya backup. Simpan file dump di luar repo dan di luar mesin lokal. Pro+ punya daily backup 7 hari di dasbor.

### 4.2 Link dan push

```bash
npx --yes supabase@latest login
npx --yes supabase@latest link --project-ref <project-ref>
npx --yes supabase@latest db push --dry-run
npx --yes supabase@latest db push
```

- `<project-ref>` adalah bagian sebelum `.supabase.co` pada Project URL.
- `link` akan meminta database password. Di CI, gunakan env `SUPABASE_DB_PASSWORD`.
- `--dry-run` menampilkan migration yang akan diterapkan. Baca daftarnya.
- **Jangan** memakai `--include-seed`. `supabase/seed.sql` hanya untuk lokal dan berisi kredensial Host dev.
- `db push` mencatat migration di `supabase_migrations.schema_migrations` dan melewati migration yang sudah pernah sukses.

Migration yang dijalankan:

| File | Isi |
|---|---|
| `0001_init_schema.sql` | ekstensi, enum, tabel, constraint, index, seed `tier_limits`/`app_config` |
| `0002_security.sql` | `app_private`, RLS, grant, publication Realtime, trigger profil |
| `0003_host_rpc.sql` | RPC Host + helper |
| `0004_guest_rpc.sql` | RPC Guest, `join_room` service-only, `record_join_failure` |
| `0005_cron_realtime.sql` | 4 job `pg_cron` + policy `typing:<room_id>` |

### 4.3 Verifikasi database

Jalankan di **SQL Editor** Supabase.

**a. Migration history**

```sql
select version, name
from supabase_migrations.schema_migrations
order by version;
```

Harus ada `0001`…`0005`.

**b. Ekstensi**

```sql
select extname, extnamespace::regnamespace as schema
from pg_extension
where extname in ('pgcrypto', 'pg_cron')
order by extname;
```

**c. RLS aktif di semua tabel public**

```sql
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;
```

Semua baris harus `rowsecurity = true`. Harus ada 9 tabel:
`app_config`, `join_attempts`, `member_activity`, `member_identities`, `messages`, `profiles`, `room_members`, `rooms`, `tier_limits`.

**d. Publication Realtime**

```sql
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
order by tablename;
```

Harus berisi `messages` dan `room_members` (hanya dua ini).

**e. Grant RPC yang sensitif**

```sql
select
  has_function_privilege('authenticated', 'public.join_room(uuid,text,text,text)', 'execute') as auth_join,
  has_function_privilege('service_role',  'public.join_room(uuid,text,text,text)', 'execute') as service_join,
  has_function_privilege('authenticated', 'public.record_join_failure(text,text)', 'execute') as auth_fail,
  has_function_privilege('service_role',  'public.record_join_failure(text,text)', 'execute') as service_fail;
```

Harus: `auth_join = false`, `service_join = true`, `auth_fail = false`, `service_fail = true`.

**f. Tidak ada RPC yang bisa dieksekusi `anon`**

```sql
select p.proname
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and has_function_privilege('anon', p.oid, 'execute')
order by p.proname;
```

Untuk RPC aplikasi, hasilnya harus kosong.

**g. Policy Realtime untuk typing**

```sql
select polname, polcmd
from pg_policy
where polrelid = 'realtime.messages'::regclass
order by polname;
```

Harus ada `typing_broadcast_select` dan `typing_broadcast_insert`. Jika tidak ada, ulangi langkah 2.3.

**h. Cron job**

```sql
select jobid, jobname, schedule, active
from cron.job
order by jobname;
```

Harus ada 4 job:

| jobname | schedule | arti |
|---|---|---|
| `delete-expired-rooms` | `0 20 * * *` | 03:00 WIB |
| `expire-pending-members` | `0 * * * *` | tiap jam |
| `purge-join-attempts` | `15 * * * *` | tiap jam |
| `release-idle-members` | `*/5 * * * *` | tiap 5 menit |

`pg_cron` memakai UTC. `delete-expired-rooms` pukul 20:00 UTC = 03:00 WIB.

Jika `cron.job` kosong, jalankan blok `select cron.schedule(...)` dari `0005_cron_realtime.sql` di SQL Editor.

**i. Cek grant tabel**

```sql
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
order by table_name, grantee, privilege_type;
```

Yang diharapkan hanya `SELECT` untuk `profiles`, `tier_limits`, `app_config`, `room_members`, dan `messages`; `rooms` memakai grant kolom, bukan grant tabel penuh. Tidak boleh ada `INSERT`/`UPDATE`/`DELETE` untuk `anon`/`authenticated`.

### 4.4 Jangan seed produksi

`supabase/seed.sql` membuat Host dev dan satu room dev (kredensialnya ada di file seed). Ini **hanya untuk lokal**. Jangan pernah menjalankan `supabase db push --include-seed` ke project produksi.

Untuk staging, buat Host manual lewat **Authentication → Users → Add user** (centang auto-confirm) atau lewat alur register setelah UI siap. Trigger `profiles` akan membuat baris profil Host non-anonim.

---

## 5. Vercel

### 5.1 Import project

1. Vercel Dashboard → **Add New → Project**.
2. Import repo GitHub yang sudah dibuat.
3. Framework preset: **Astro** (biasanya terdeteksi otomatis).
4. Root directory: repo root.
5. Build command: `npm run build`.
6. Install command: `npm ci`.
7. Output: biarkan otomatis (adapter Vercel menghasilkan `.vercel/output`).
8. **Node.js version: 22.x** (Project Settings → General → Node.js Version).
9. Jika plan Vercel mengizinkan, pilih region function yang dekat dengan region Supabase (mis. Singapura) untuk mengurangi latency.

Jangan memakai Node 24/26 tanpa menguji ulang seluruh build dan runtime.

> **Batas Hobby:** Vercel Hobby tidak bisa mengimpor repo yang dimiliki **GitHub organization**. Jika repo berada di organization, pindahkan ke akun pribadi atau gunakan Vercel Pro/Team.

### 5.2 Environment variables

Buka **Project Settings → Environment Variables**. Isi untuk **Production** dan **Preview** (tambahkan juga Development jika memakai `vercel dev`).

| Nama | Nilai | Sumber | Rahasia? |
|---|---|---|---|
| `PUBLIC_SUPABASE_URL` | `https://<ref>.supabase.co` | Supabase Project URL | tidak |
| `PUBLIC_SUPABASE_ANON_KEY` | `sb_publishable_...` atau `anon` JWT | Supabase API Keys | tidak (memang publik) |
| `PUBLIC_TURNSTILE_SITE_KEY` | site key Turnstile | Cloudflare | tidak |
| `SUPABASE_SERVICE_ROLE_KEY` | `sb_secret_...` atau `service_role` JWT | Supabase API Keys | **ya** |
| `TURNSTILE_SECRET_KEY` | secret key Turnstile | Cloudflare | **ya** |
| `IP_HASH_SALT` | string acak ≥ 32 karakter | generate sendiri | **ya** |

Generate salt:

```bash
openssl rand -hex 32
```

Aturan:

- `PUBLIC_*` **di-inline saat build**. Jika nilainya berubah, redeploy — restart function saja tidak cukup.
- Secret hanya dibaca di server. Jangan pernah memberi awalan `PUBLIC_`.
- Tandai `SUPABASE_SERVICE_ROLE_KEY`, `TURNSTILE_SECRET_KEY`, dan `IP_HASH_SALT` sebagai **Sensitive** di Vercel.
- Jangan memakai nilai yang sama antara production dan staging jika memungkinkan.
- `IP_HASH_SALT` harus stabil. Menggantinya membuat hash di `join_attempts` lama tidak cocok, sehingga lockout lama tidak berlaku.

Jika memakai Preview deployment dengan database produksi, siapa pun yang punya URL preview bisa memakai service key lewat endpoint. Pilihan yang lebih aman:

- buat Supabase project kedua untuk staging, atau
- aktifkan Vercel Deployment Protection untuk Preview, dan jangan pakai service key produksi di Preview.

### 5.3 Domain

1. Project → **Settings → Domains** → **Add**.
2. Masukkan subdomain final, mis. `room.example.com`.
3. Vercel menampilkan nilai DNS yang harus dibuat. Salin **persis** nilai itu; jangan menebak.
4. Jika Vercel meminta TXT verification, tambahkan di Cloudflare.
5. Tunggu sampai status **Valid Configuration**.

Jangan memakai `*.vercel.app` sebagai domain produksi: Turnstile hostname, Supabase Site URL, dan cookie/auth redirect harus konsisten.

### 5.4 Rate limit join (Vercel WAF)

Endpoint `POST /api/rooms/join` adalah target utama penyalahgunaan.

1. Project → **Firewall → Rules → Create Rule**.
2. Name: `join-rate-limit`.
3. Kondisi:
   - Request Path **equals** `/api/rooms/join`
   - Request Method **equals** `POST`
4. Rate limit: mis. **20 requests per 60 seconds per IP**.
5. Action: **Deny** (429).

Hobby hanya punya **1 rate-limit rule** per project (dan maksimal 3 custom firewall rules). Sesuaikan angka setelah melihat trafik; 20/menit bisa terlalu ketat untuk jaringan sekolah/kantor yang berbagi IP.

Rate limit ini pelengkap, bukan pengganti lockout aplikasi:

- `join_attempts` menangani salah password (5 gagal/15 menit → lockout 15 menit).
- `room_failure_cap_per_hour` (200/jam) + `room_cooldown_minutes` (10) menangani brute force per room.
- Agent B **wajib** memanggil `record_join_failure` setelah `join_room` mengembalikan `WRONG_PASSWORD`; tanpa itu lockout tidak pernah terisi.

### 5.5 Deploy pertama

Setelah env dan domain siap:

1. **Deploy** (atau push ke `main`).
2. Buka build log. Pastikan:
   - tidak ada `sb_secret_`, `service_role`, atau isi secret lain yang tercetak;
   - build sukses di Node 22.x;
   - tidak ada error `astro:env` karena `PUBLIC_*` hilang.
3. Buka URL produksi. Untuk saat ini yang diharapkan hidup hanya shell dan `/api/health`.

### 5.6 Deployment protection

- **Production** harus bisa diakses publik (Guest membuka `/r/<slug>`).
- **Preview** boleh dilindungi Vercel Authentication.
- Jangan mengaktifkan protection pada production domain; link room tidak akan bisa dibuka Guest.

---

## 6. DNS Cloudflare (DNS-only)

Keputusan project: **Cloudflare hanya DNS, tanpa proxy**. Awan harus **abu-abu**.

1. Cloudflare Dashboard → pilih domain → **DNS → Records → Add record**.
2. Type: **CNAME**.
3. Name: subdomain, mis. `room`.
4. Target: nilai dari Vercel (biasanya `cname.vercel-dns.com`, tetapi pakai yang ditampilkan Vercel).
5. Proxy status: **DNS only** (jangan oranye).
6. TTL: Auto.

Verifikasi:

```bash
dig +short room.example.com CNAME
```

Setelah propagasi, Vercel harus menunjukkan **Valid Configuration** dan sertifikat TLS terbit.

Jangan menyalakan proxy Cloudflare untuk saat ini. Jika suatu hari diubah, set SSL/TLS **Full (strict)** dan uji WebSocket Realtime; tetapi itu di luar keputusan MVP.

---

## 7. GitHub Actions

### 7.1 Secret keep-alive

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

- Name: `SITE_URL`
- Value: `https://room.example.com` (tanpa trailing slash)

Workflow `.github/workflows/keepalive.yml` memanggil:

```text
GET https://room.example.com/api/health?db=1
```

Jadwal: Senin & Kamis 03:00 UTC. Ini mencegah project Supabase free di-pause setelah 7 hari tanpa aktivitas.

Uji manual:

1. Actions → **keepalive** → **Run workflow**.
2. Pastikan step `Ping health + DB` sukses (curl `-f` gagal pada status non-2xx).

Catatan penting: `/api/health?db=1` tetap mengembalikan **HTTP 200** dengan `db: "error"` jika database gagal. Workflow saat ini hanya memeriksa status HTTP, jadi hijau belum tentu DB sehat. Untuk monitoring yang lebih ketat, ubah step menjadi:

```bash
curl -fsS "${{ secrets.SITE_URL }}/api/health?db=1" | grep -q '"db":"ok"'
```

Perubahan workflow adalah zona L; minta L menerapkannya jika ingin alarm DB yang sebenarnya.

Catatan lain:

- GitHub menonaktifkan workflow terjadwal di repo **publik** yang tidak ada aktivitas 60 hari. Repo private lebih aman; jika publik, cek dan aktifkan ulang secara berkala.
- Workflow hanya melakukan ping; tidak membocorkan data.

### 7.2 CI

`.github/workflows/ci.yml` memakai `PUBLIC_*` placeholder untuk `npm run build`. Jangan menambahkan service role key ke CI. Jika nanti T-20 membuat secret server wajib saat build, gunakan nilai dummy khusus build, bukan kunci produksi.

---

## 8. Smoke test setelah deploy

### 8.1 Health

```bash
curl -i https://room.example.com/api/health
curl -i 'https://room.example.com/api/health?db=1'
```

Harapan:

- HTTP 200.
- Body pertama: `{"ok":true,"time":"..."}`.
- Body kedua: `db` bernilai `"ok"`.

Jika `db` bernilai `"error"`:

- cek `SUPABASE_SERVICE_ROLE_KEY` di Vercel,
- cek `PUBLIC_SUPABASE_URL`,
- cek apakah project Supabase sedang pause,
- cek Logs Vercel untuk error yang tidak membocorkan secret.

### 8.2 Header keamanan

```bash
curl -sI https://room.example.com/ | grep -Ei \
  'referrer-policy|x-content-type-options|x-frame-options|permissions-policy'
```

Harapan: `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, dan `Permissions-Policy` sesuai `vercel.json`.

Cek noindex:

```bash
curl -sI https://room.example.com/r/contoh | grep -i x-robots-tag
curl -sI https://room.example.com/dashboard | grep -i x-robots-tag
```

Harapan: `noindex`.

CSP belum ada di `vercel.json`; T-22 akan menambahkannya. Setelah T-22, pastikan CSP mengizinkan:

- `https://<ref>.supabase.co` dan `wss://<ref>.supabase.co`
- `https://challenges.cloudflare.com` (script + frame Turnstile)

Jika Turnstile tidak muncul atau Realtime gagal connect, buka console browser dan cek pelanggaran CSP.

### 8.3 Auth anonymous + Turnstile

Setelah UI Guest ada (T-52):

1. Buka `/r/<slug>`.
2. Selesaikan Turnstile.
3. Pastikan anonymous session terbentuk (bukan error `Anonymous sign-ins are disabled`).
4. Pastikan CAPTCHA Supabase tidak menolak token.

Jika gagal:

- `Anonymous sign-ins are disabled` → aktifkan di Authentication → Providers.
- `captcha protection: request disallowed` → secret Turnstile di Supabase salah/kosong, atau token tidak dikirim.
- `timeout-or-duplicate` → token dipakai ulang; reset widget.

### 8.4 Join (setelah T-21)

`POST /api/rooms/join` saat ini mengembalikan **501**. Setelah T-21, uji:

- password salah → 401/403 dengan kode yang benar, dan `join_attempts` bertambah;
- 5 kali salah, percobaan berikutnya → `LOCKED` + `Retry-After`;
- room penuh → kode kapasitas;
- password benar → member `PENDING` atau `APPROVED` sesuai setelan room;
- Turnstile gagal → 403 `TURNSTILE_FAILED`;
- tanpa Bearer token → 401.

Jangan menguji lockout di produksi dengan akun orang lain. Gunakan staging.

### 8.5 Realtime

Setelah UI chat ada (T-53):

1. Buka satu room dengan dua browser/dua akun.
2. Kirim pesan; pastikan muncul di kedua sisi.
3. Buka channel `typing:<room_id>` dengan `config: { private: true }`.
4. Kick salah satu Guest dari panel Host.
5. Catat keterbatasan yang sudah diketahui: channel yang **sudah terbuka** masih bisa mengirim/menerima Broadcast sampai reconnect. Client wajib `unsubscribe` saat status bukan `APPROVED`.

Jika channel private gagal subscribe:

- pastikan **Allow public access to channels** sudah dimatikan;
- pastikan policy `typing_broadcast_select`/`insert` ada;
- pastikan client memakai `private: true`;
- pastikan Realtime Auth memakai JWT terbaru (`supabase.realtime.setAuth()`).

### 8.6 Secret scan

Di mesin lokal, setelah build:

```bash
grep -rInE 'SUPABASE_SERVICE_ROLE_KEY|TURNSTILE_SECRET_KEY|IP_HASH_SALT|sb_secret_' \
  dist/client .vercel/output/static 2>/dev/null || true
```

Harus kosong. Jangan menempelkan nilai secret asli ke dalam perintah grep atau log.

Di Vercel, buka build log dan cari nama variabel secret; pastikan nilainya tidak tercetak.

### 8.7 Cron dan database

```sql
select jobname, schedule, active from cron.job order by jobname;

select jobid, jobname, status, return_message, start_time
from cron.job_run_details
order by start_time desc
limit 20;

select pg_size_pretty(pg_database_size(current_database())) as db_size;
```

Pastikan job berstatus `succeeded` dan tidak ada `failed` berulang.

---

## 9. Monitoring dan operasi rutin

### 9.1 Kuota Supabase free

Angka yang dipakai TASK.md (cek ulang di dasbor):

- Realtime: **±200 koneksi bersamaan**, **2 juta pesan/bulan**.
- Database: **500 MB**.
- Auth: **50.000 MAU** (anonymous user ikut dihitung).
- Project **di-pause setelah 7 hari tanpa aktivitas**.
- **Tidak ada backup otomatis** di Free.
- Pesan Realtime dihitung **per penerima**. Room 40 Guest berarti satu pesan chat ≈ 40 hitungan; Broadcast typing juga dihitung.

Pantau:

- **Reports → Realtime**: pesan/bulan, koneksi puncak.
- **Reports → Database**: ukuran DB, koneksi, query lambat.
- **Reports → Auth**: MAU, anonymous users.
- **Reports → API**: request dan error.
- **Logs**: API/Auth/Realtime/Postgres. Free plan hanya menyimpan log sekitar 1 hari; ekspor atau catat temuan penting sebelum hilang.

Catatan: setiap Guest adalah user anonymous baru. User anonymous menumpuk dan bisa memengaruhi MAU. Belum ada job cleanup `auth.users`; jangan menghapus user sembarangan karena `member_identities` ikut cascade. Jika perlu cleanup, rancang dulu bersama D/S.

### 9.2 Keep-alive

- Workflow `keepalive` harus sukses Senin & Kamis.
- Jika gagal 2 kali berturut-turut, cek:
  - `SITE_URL` masih benar,
  - domain/TLS,
  - `/api/health?db=1` mengembalikan `db: "ok"`,
  - project Supabase tidak pause.

### 9.3 Cron

Cek berkala:

```sql
select jobname, status, return_message, start_time
from cron.job_run_details d
join cron.job j using (jobid)
where d.status <> 'succeeded'
order by d.start_time desc
limit 20;
```

Jika `release-idle-members` gagal, kursi idle tidak dilepas oleh cron; akses tetap diblokir RLS dan pelepasan lazy saat room penuh masih bekerja. Tetap perbaiki job.

### 9.4 Vercel

- **Logs**: cari 5xx, 429, error `SUPABASE_SERVICE_ROLE_KEY belum diset`, error Turnstile.
- **Firewall**: pantau rule `join-rate-limit`; jika terlalu banyak 429, naikkan batas atau longgarkan kondisi.
- **Analytics**: latency function dan error rate.
- **Deployments**: rollback cepat jika rilis baru rusak.

Jangan log body request, password, token, atau IP mentah. Log hanya kode error dan metadata aman.

### 9.5 Turnstile

Cloudflare Dashboard → Turnstile → widget:

- pantau solve rate dan failure;
- jika banyak `timeout-or-duplicate`, cek UI tidak memakai token ulang;
- jika banyak `invalid-input-response`, cek hostname widget dan site key.

### 9.6 Alert minimum

- GitHub Actions failure notification untuk `keepalive`.
- Supabase usage alert (jika tersedia di plan).
- Vercel deployment failure notification.
- Catat tanggal pengecekan kuota di `docs/progress.md` atau catatan operasi.

---

## 10. Backup, rollback, dan insiden

### 10.1 Backup

Sebelum migration besar:

```bash
npx --yes supabase@latest db dump --linked -f backup-schema.sql
npx --yes supabase@latest db dump --linked --data-only -f backup-data.sql
```

**Free plan tidak punya backup otomatis.** `db dump` adalah backup utama; simpan salinannya off-site (mis. storage pribadi) dan jangan mengandalkan repo Git untuk data. Pro+ menyediakan daily backup 7 hari di **Database → Backups**. `db dump` tidak menyertakan schema `auth`/`storage`; untuk MVP, akun Host bisa dibuat ulang, tetapi koordinasikan dengan manusia sebelum restore.

### 10.2 Rollback Vercel

- Deployments → pilih deployment terakhir yang sehat → **Promote to Production** / **Rollback**.
- Rollback Vercel tidak mengubah database. Jika rilis membawa migration yang tidak kompatibel, siapkan migration perbaikan.

### 10.3 Rollback database

- Migration bersifat **forward-only**. Jangan mengedit migration yang sudah diterapkan.
- Buat migration baru untuk memperbaiki schema/data.
- `supabase migration repair` hanya memperbaiki history, bukan mengembalikan schema. Jangan pakai tanpa memahami risikonya.
- Untuk insiden serius di Pro+, restore dari backup dasbor. Di Free, restore dari dump manual; koordinasikan dengan manusia.

### 10.4 Tombol darurat

Jika terjadi penyalahgunaan:

1. Matikan **Anonymous sign-ins** di Supabase Auth → Guest baru tidak bisa masuk (sesi lama masih jalan).
2. Blokir `/api/rooms/join` di Vercel WAF.
3. Tutup room yang bermasalah lewat RPC `close_room` (Host) atau operasi SQL terkontrol.
4. Rotasi `SUPABASE_SERVICE_ROLE_KEY`/secret dan `TURNSTILE_SECRET_KEY`; update Vercel; redeploy.
5. Jangan menghapus tabel atau data tanpa backup.

---

## 11. Batasan dan blocker yang diketahui

1. **`POST /api/rooms/join` masih 501** sampai T-21. Jangan mengumumkan MVP bisa dipakai.
2. **UI Guest/Host belum ada** sampai T-31/T-50…T-53.
3. **Audit keamanan belum** (T-60…T-64). Jangan rilis publik sebelum temuan high diselesaikan.
4. **Realtime kick**: channel yang sudah terbuka tetap bisa Broadcast sampai reconnect. Client wajib unsubscribe saat status bukan `APPROVED`; ini batasan Supabase Realtime, bukan bug yang bisa ditutup dari SQL.
5. **Public channels**: wajib dimatikan di Realtime Settings. Tanpa itu, siapa pun dengan anon key bisa subscribe channel publik.
6. **Seed produksi**: jangan pernah `--include-seed`.
7. **Kunci API Supabase**: `anon`/`service_role` dipensiunkan akhir 2026. Migrasi ke publishable/secret sebelum itu.
8. **Node**: butuh 22.22+; set 22.x di Vercel. Node 24/26 belum diuji untuk produksi.
9. **Rate limit Hobby**: hanya 1 rule. Manfaatkan untuk `/api/rooms/join`.
10. **Free plan**: project pause setelah 7 hari tanpa aktivitas; keep-alive harus jalan.
11. **Email Host**: default TASK aktif; butuh SMTP produksi. Jika dimatikan, catat sebagai keputusan manusia.
12. **`npm audit`**: 3 temuan high dari `path-to-regexp` via `@astrojs/vercel` (build-time). Jangan `npm audit fix --force`.
13. **`record_join_failure`**: harus dipanggil B setelah `WRONG_PASSWORD`; jika tidak, lockout tidak aktif.

---

## 12. Checklist ringkas

### Supabase

- [ ] Project baru, terpisah dari menfess/form.
- [ ] Slot project Free plan cukup (maks. 2 aktif/organization) atau sudah upgrade.
- [ ] Project URL, publishable/anon, secret/service_role dicatat.
- [ ] Anonymous sign-ins aktif.
- [ ] Turnstile CAPTCHA aktif dengan secret yang benar.
- [ ] Site URL + redirect URLs production/localhost.
- [ ] Keputusan email confirmation + SMTP.
- [ ] Realtime enabled; **Allow public access to channels dimatikan**.
- [ ] `pg_cron`/`pgcrypto` aktif.
- [ ] `supabase link` + `db push --dry-run` + `db push`.
- [ ] 0001…0005 ada di migration history.
- [ ] RLS semua tabel public aktif.
- [ ] Publication hanya `messages` + `room_members`.
- [ ] Grant `join_room`/`record_join_failure` hanya `service_role`.
- [ ] Policy `typing_broadcast_select`/`insert` ada.
- [ ] 4 cron job aktif.
- [ ] Seed produksi tidak dijalankan.

### Turnstile

- [ ] Widget production + localhost.
- [ ] Site key + secret disimpan.
- [ ] Token baru untuk auth dan join (tidak dipakai ulang).

### Vercel

- [ ] Repo Git dibuat dan di-push; `.env` tidak ikut commit.
- [ ] Repo bisa diimpor Vercel (bukan GitHub organization untuk Hobby).
- [ ] Project Vercel baru, Node 22.x.
- [ ] 6 env var terisi untuk Production + Preview.
- [ ] Secret ditandai Sensitive.
- [ ] Domain ditambahkan; status Valid Configuration.
- [ ] Rate limit `POST /api/rooms/join` aktif.
- [ ] Deploy pertama sukses; build log bersih dari secret.
- [ ] Production tidak dilindungi Deployment Protection.

### DNS

- [ ] CNAME dari Vercel.
- [ ] Proxy **DNS only** (abu-abu).
- [ ] TLS terbit; `dig` benar.

### GitHub

- [ ] Secret `SITE_URL` benar.
- [ ] Keepalive dijalankan manual dan sukses.
- [ ] CI hijau.

### Setelah deploy

- [ ] `/api/health` 200.
- [ ] `/api/health?db=1` → `db: "ok"`.
- [ ] Header keamanan + noindex benar.
- [ ] Auth anonymous + Turnstile berhasil (setelah UI).
- [ ] Join diuji (setelah T-21).
- [ ] Realtime private channel diuji (setelah T-53).
- [ ] Secret scan kosong.
- [ ] Cron `succeeded`.
- [ ] Backup manual pertama (`db dump`) disimpan off-site.
- [ ] Keepalive manual sukses; pertimbangkan cek `db: "ok"` di workflow.
- [ ] Monitoring kuota dicatat.
- [ ] Blocker T-21/T-52/T-64/T-72 sudah ditutup sebelum rilis publik.

---

## 13. Perintah referensi cepat

```bash
# lokal
npm ci
npm test
npm run check
npm run build
npx --yes supabase@latest start
npx --yes supabase@latest db reset
npx --yes supabase@latest test db

# hosted
npx --yes supabase@latest login
npx --yes supabase@latest link --project-ref <ref>
npx --yes supabase@latest db push --dry-run
npx --yes supabase@latest db push

# backup
npx --yes supabase@latest db dump --linked -f backup-schema.sql
npx --yes supabase@latest db dump --linked --data-only -f backup-data.sql

# smoke test
curl -fsS https://<subdomain>/api/health
curl -fsS 'https://<subdomain>/api/health?db=1'
```

---

## 14. Rujukan

- `docs/setup.md` — checklist manual T-70/T-71.
- `TASK.md` bagian 3–9, 12–14 — kontrak dan batasan.
- `supabase/migrations/0001…0005` — schema, RLS, RPC, cron, Realtime policy.
- `supabase/seed.sql` — hanya untuk lokal.
- `.env.example` — daftar env.
- `vercel.json` — header keamanan dan noindex.
- `.github/workflows/keepalive.yml` — keep-alive Supabase.
- `src/pages/api/health.ts` — endpoint health.
- Supabase Realtime Settings: <https://supabase.com/dashboard/project/_/realtime/settings>
- Supabase API Keys: <https://supabase.com/dashboard/project/_/settings/api-keys>
- Vercel WAF Rate Limiting: <https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting>
