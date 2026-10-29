# TASK.md — Spesifikasi & kontrak (umpomenfess-room)

Dokumen ini adalah **sumber kebenaran** untuk semua agent. Menggantikan `docs/PRD_v2.docx` bila ada perbedaan.
Angka bertanda **(usulan)** boleh diubah manusia lewat tabel konfigurasi tanpa mengubah kode.

## 1. Ringkasan

Room chat teks anonim. **Host** (akun email/password) membuat room dan memegang moderasi. **Guest** masuk tanpa akun memakai link + password, tampil sebagai `Guest-01`, `Guest-02`, dst. Room aktif 7 hari, lalu read-only 15 hari (Host bisa ekspor .txt), lalu dihapus permanen.

Fitur tambahan versi ini: **kapasitas room per tier**, **auto-kick Guest idle**, **Guest boleh di banyak room tanpa login**, **indikator mengetik**.

## 2. Keputusan terkunci

| ID | Keputusan |
|---|---|
| D-01 | Astro SSR + Vercel + React island. Supabase untuk Postgres/Auth/Realtime/RLS. Tanpa Socket.io. |
| D-02 | Cloudflare DNS-only. Turnstile di register, join, dan CAPTCHA Supabase Auth (anonymous sign-in). |
| D-03 | Guest = Anonymous Sign-in. Satu browser = satu `auth.uid()` untuk semua room. Keanggotaan disimpan di DB. |
| D-04 | Semua tulis lewat RPC. Tidak ada policy INSERT/UPDATE/DELETE untuk client. |
| D-05 | Host tidak melihat `user_id` Guest: tabel `room_members` (terlihat Host) dipisah dari `member_identities` (privat). |
| D-06 | Password room: 6 karakter dari alfabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (tanpa karakter mirip), acak kriptografis, di-hash `crypt(pw, gen_salt('bf', 10))`, **tampil sekali**, input dibandingkan case-insensitive (di-uppercase). |
| D-07 | Status room dihitung dari waktu, bukan menunggu cron. |
| D-08 | Mengetik = Broadcast agregat tanpa identitas, per-room toggle, ada kill switch global. |
| D-09 | Kapasitas dipilih Host saat membuat room, dibatasi cap tier. |
| D-10 | "Kursi" = member berstatus `APPROVED`. Kursi idle dilepas secara lazy (saat ada yang masuk) plus cron. |
| D-11 | Guest boleh di banyak room, maks 5 keanggotaan aktif (`APPROVED`+`PENDING`). |
| D-12 | Pembayaran belum ada. `tier` diubah manual. |
| D-13 | Setelah room CLOSED, Guest kehilangan akses total. Hanya Host yang bisa membaca dan ekspor. (usulan, belum dikonfirmasi) |

## 3. Konfigurasi (di database, bukan hard-coded)

`tier_limits` (seed):

| tier | max_active_rooms | max_guests_cap | max_messages_per_room |
|---|---|---|---|
| free | 3 | 40 | 5000 |
| premium | 10 (usulan) | 75 | 20000 (usulan) |

`app_config` (key → value, seed):

| key | nilai | arti |
|---|---|---|
| message_max_length | 2000 | karakter per pesan |
| messages_per_minute | 20 | rate kirim per member |
| max_rooms_per_guest | 5 | keanggotaan aktif per `auth.uid()` |
| password_length | 6 | |
| lockout_fail_threshold | 5 | gagal per (room, ip_hash) |
| lockout_window_minutes | 15 | jendela hitung gagal |
| lockout_duration_minutes | 15 | lama kunci sejak gagal terakhir |
| room_failure_cap_per_hour | 200 | total gagal per room per jam |
| room_cooldown_minutes | 10 | semua join ditolak setelah cap tercapai |
| room_active_days | 7 | |
| room_grace_days | 15 | |
| pending_ttl_hours | 24 | PENDING lebih lama → `LEFT` |
| pending_cap_multiplier | 2 | maks PENDING = 2 × max_guests |
| typing_global_enabled | true | kill switch |
| typing_default_on_max_guests | 20 | default toggle ON bila max_guests ≤ nilai ini |

Batas infrastruktur free plan yang harus diperhatikan (dicek Oktober 2026, verifikasi ulang): Supabase ±200 koneksi Realtime bersamaan, 2 juta pesan Realtime/bulan, DB 500 MB, proyek di-pause setelah 7 hari tidak aktif. **Pesan Realtime dihitung per penerima** (database change = 1 per client yang mendengarkan; Broadcast = 1 terkirim + 1 per penerima). Room 40 Guest berarti satu pesan chat ≈ 40 hitungan. Pantau di dasbor usage.

## 4. Data model (schema `public`, RLS aktif di semua)

- `profiles(user_id pk → auth.users on delete cascade, tier text not null default 'free' check in ('free','premium'), created_at)`. Dibuat oleh trigger saat user **non-anonim** mendaftar.
- `tier_limits`, `app_config` seperti bagian 3.
- `rooms(id uuid pk, slug text unique not null, host_id uuid not null → auth.users on delete cascade, name text check 1..80, password_hash text not null, password_version int not null default 1, approval_required bool not null, max_guests int not null check 2..75, idle_timeout_minutes int not null default 30 check 10..240, typing_enabled bool not null, member_counter int not null default 0, created_at, expires_at, closed_at null, delete_at)`.
  - `slug`: 16 karakter `[A-Za-z0-9_-]` dari `gen_random_bytes`. Tidak berurutan.
  - `expires_at = created_at + room_active_days`. `delete_at = expires_at + room_grace_days`; saat tutup manual menjadi `closed_at + room_grace_days`.
  - **Status turunan**: `ACTIVE` jika `closed_at is null and now() < expires_at`, selain itu `CLOSED`.
- `room_members(id uuid pk, room_id → rooms on delete cascade, member_no int null, display_name text null, status member_status not null, password_version int not null, created_at, status_changed_at, unique(room_id, member_no))`.
  - enum `member_status`: `PENDING`, `APPROVED`, `REJECTED`, `KICKED`, `IDLE`, `LEFT`.
  - `member_no`/`display_name` ("Guest-07") diberikan **sekali**, saat pertama kali `APPROVED`, dan dipertahankan bila kembali.
- `member_identities(member_id pk → room_members on delete cascade, room_id, user_id uuid not null, unique(room_id, user_id))`. **Tidak ada policy**: hanya fungsi `SECURITY DEFINER` yang menyentuhnya. Index di `user_id`.
- `member_activity(member_id pk → room_members on delete cascade, last_active_at timestamptz not null)`. Tidak masuk publication Realtime.
- `messages(id bigint generated always as identity pk, room_id → rooms on delete cascade, sender_type ('HOST','GUEST'), member_id null → room_members, sender_name text not null, content text not null check length ≤ 2000, client_msg_id uuid not null, created_at, unique(room_id, client_msg_id))`. Index `(room_id, id desc)`. Paginasi memakai `id`, bukan `created_at`.
- `join_attempts(id bigint, room_id, ip_hash text, success bool, created_at)`. Index `(room_id, ip_hash, created_at)`. Dihapus setelah 24 jam.

## 5. RLS, privilege, publication

- `REVOKE ALL` pada semua tabel dan fungsi dari `PUBLIC`, `anon`, `authenticated`. `ALTER DEFAULT PRIVILEGES` agar objek baru ikut tertutup. Berikan hanya yang tercantum di bawah.
- Fungsi pembantu di schema privat `app_private` (`SECURITY DEFINER`, `STABLE`, `search_path=''`): `is_room_host(room_id)`, `is_approved_member(room_id)`, `is_self_member(member_id)`, `room_is_active(room_id)`, `room_is_readable_by_host(room_id)` (`now() < delete_at`).
- Policy (semua `TO authenticated`, hanya SELECT):
  - `messages`: Host pemilik room dan `now() < delete_at`; atau `is_approved_member(room_id)` dan `room_is_active(room_id)`.
  - `room_members`: Host pemilik room; atau `is_self_member(id)`.
  - `rooms`: `GRANT SELECT (id, slug, name, approval_required, max_guests, idle_timeout_minutes, typing_enabled, created_at, expires_at, closed_at, delete_at, password_version)` + policy `host_id = auth.uid()`. **Kolom `password_hash` tidak diberi grant.**
  - `profiles`: baris sendiri. `tier_limits`, `app_config`: semua authenticated.
  - `member_identities`, `member_activity`, `join_attempts`: RLS aktif, **tanpa policy** (tolak semua).
- Publication `supabase_realtime`: hanya `messages` dan `room_members`.
- Realtime Authorization (`realtime.messages`): izinkan `SELECT`/`INSERT` ber-extension broadcast untuk topic `typing:<room_id>` hanya bagi Host atau member `APPROVED` pada room `ACTIVE` dengan fitur mengetik aktif. Matikan akses channel publik di pengaturan Realtime (jika tersedia) agar channel wajib private.

## 6. Kontrak RPC

Konvensi: error = `ERRCODE 'P0001'`, `MESSAGE` = kode di bawah, `DETAIL` = JSON opsional (mis. `{"retry_after":600}`). Client memetakan berdasarkan `error.message`.

**Host** (`authenticated`, JWT **non-anonim** wajib, else `NOT_HOST`):

| RPC | Argumen | Mengembalikan | Error |
|---|---|---|---|
| `create_room` | `p_name, p_max_guests, p_approval_required, p_idle_timeout_minutes, p_typing_enabled` | `room_id, slug, password (plaintext, sekali), expires_at` | `INVALID_INPUT`, `CAPACITY_EXCEEDS_TIER`, `QUOTA_REACHED` |
| `regenerate_password` | `p_room_id` | `password` (sekali). Menaikkan `password_version`. | `NOT_FOUND`, `ROOM_CLOSED` |
| `update_room_settings` | `p_room_id` + `p_approval_required, p_max_guests, p_idle_timeout_minutes, p_typing_enabled` (null = tetap) | baris room | `CAPACITY_EXCEEDS_TIER`, `CAPACITY_BELOW_MEMBERS`, `ROOM_CLOSED` |
| `close_room` | `p_room_id` | void. Set `closed_at`, hitung ulang `delete_at`. | `NOT_FOUND` |
| `decide_member` | `p_member_id, p_decision ('APPROVE'\|'REJECT')` | `id, display_name, status` | `NOT_FOUND`, `NOT_PENDING`, `ROOM_FULL`, `ROOM_CLOSED` |
| `kick_member` | `p_member_id` | void (status `KICKED`) | `NOT_FOUND` |
| `list_members` | `p_room_id` | `id, display_name, status, created_at` (**tanpa user_id**) | `NOT_FOUND` |
| `list_hosted_rooms` | — | room + status turunan + `approved_count`, `pending_count`, kuota `{used, max}` | — |
| `export_messages` | `p_room_id, p_after_id default 0, p_limit default 1000` | pesan urut naik | `NOT_FOUND` |

**Guest/member** (`authenticated`, termasuk anonim):

| RPC | Argumen | Mengembalikan | Error |
|---|---|---|---|
| `get_room_public` | `p_slug` | `room_id, name, status ('ACTIVE'\|'CLOSED'), typing_effective` | `NOT_FOUND` |
| `rejoin_room` | `p_room_id` | `status`. Hanya untuk `IDLE` dengan `password_version` sama. | `NOT_MEMBER`, `KICKED`, `ROOM_CLOSED`, `ROOM_FULL`, `PASSWORD_CHANGED` |
| `my_rooms` | — | `room_id, slug, name, room_status, my_status, display_name, expires_at` (room ACTIVE saja) | — |
| `list_messages` | `p_room_id, p_before_id null, p_after_id null, p_limit default 50 (maks 100)` | pesan | `NOT_MEMBER`, `ROOM_CLOSED` |
| `send_message` | `p_room_id, p_content, p_client_msg_id` | baris pesan. **Idempotent** pada `client_msg_id`. Sender diturunkan dari DB. Memperbarui `last_active_at`. | `NOT_MEMBER`, `ROOM_CLOSED`, `MESSAGE_TOO_LONG`, `RATE_LIMITED`, `ROOM_MESSAGE_LIMIT` |
| `touch_activity` | `p_room_id` | status member saat ini (`APPROVED`, `IDLE`, `KICKED`, ...) | `NOT_MEMBER` |
| `leave_room` | `p_room_id` | void (status `LEFT`, kursi lepas) | `NOT_MEMBER` |

**Khusus server** (`service_role` saja; **tidak** boleh bisa dipanggil `authenticated`/`anon`):

`join_room(p_user_id uuid, p_slug text, p_password text, p_ip_hash text)` → `status, room_id, member_id, display_name`.
Urutan wajib:
1. Room tidak ada → `ROOM_NOT_FOUND`. Room CLOSED → `ROOM_CLOSED`.
2. Cooldown room (gagal ≥ `room_failure_cap_per_hour` dalam 1 jam) → `ROOM_COOLDOWN`. Lockout (gagal ≥ 5 dalam 15 menit untuk `(room, ip_hash)`) → `LOCKED` + `retry_after`.
3. Jika `p_user_id` sudah member `KICKED` → `KICKED`; `REJECTED` → `REJECTED`. Member `PENDING`/`APPROVED` → kembalikan status saat ini (bukan percobaan password).
4. Verifikasi password (case-insensitive). Salah → catat gagal, `WRONG_PASSWORD`. Benar → catat berhasil.
5. Keanggotaan aktif `p_user_id` (APPROVED+PENDING di room ACTIVE lain) ≥ `max_rooms_per_guest` → `MAX_ROOMS_PER_GUEST`.
6. `release_idle_members(room)` (lazy). Jika `approval_required` → `PENDING` (tolak `ROOM_FULL` bila PENDING ≥ cap). Jika tidak → bila kursi `APPROVED` < `max_guests` jadi `APPROVED` dengan penomoran atomik, selain itu `ROOM_FULL`.
7. Baris `IDLE`/`LEFT` milik user yang sama dipakai ulang (nomor lama dipertahankan).

Penomoran atomik: `UPDATE rooms SET member_counter = member_counter + 1 ... RETURNING member_counter` dalam transaksi yang sama dengan perubahan status.

**Internal/cron** (tanpa grant ke client): `release_idle_members(p_room_id default null)`, `expire_pending_members()`, `purge_join_attempts()`, `delete_expired_rooms()`.

## 7. API server (Astro)

`POST /api/rooms/join` — body `{ slug, password, turnstileToken }`, header `Authorization: Bearer <access_token sesi anonim>`.

1. Validasi `joinRequestSchema` (zod).
2. `verifyTurnstile(token, ip)`; gagal → 403 `TURNSTILE_FAILED`.
3. `verifyAccessToken(token)` → `user_id`; gagal → 401.
4. `hashIp(clientAddress, IP_HASH_SALT)`. Jangan percaya header IP dari client selain yang disediakan adapter Vercel.
5. Panggil RPC `join_room` dengan `service_role`.
6. Petakan error: `WRONG_PASSWORD`→401, `LOCKED`/`ROOM_COOLDOWN`→429 (+`Retry-After`), `ROOM_FULL`/`MAX_ROOMS_PER_GUEST`/`KICKED`/`REJECTED`/`ROOM_CLOSED`→403 dengan `code`, `ROOM_NOT_FOUND`→404. Respons sukses: `{ status, roomId, memberId, displayName }`.
7. Satu rule rate limit Vercel WAF pada path ini (dipasang manusia).

`GET /api/health[?db=1]` sudah ada (dipakai keep-alive).

## 8. Realtime & perilaku client

- **Pesan**: Postgres Changes `INSERT` pada `messages` filter `room_id=eq.<id>`. Saat `SUBSCRIBED` (termasuk reconnect) panggil `list_messages(p_after_id = id terakhir)` untuk menambal pesan yang terlewat. Dedupe berdasarkan `id` dan `client_msg_id`. Kirim optimistis dengan `client_msg_id` baru.
- **Status member**: Postgres Changes pada `room_members` filter `room_id`. Guest hanya menerima barisnya sendiri (RLS), Host menerima semua.
- **Riwayat**: 50 pesan terakhir saat masuk, scroll ke atas memuat lebih lama (`p_before_id`).
- **Heartbeat**: saat tab `visible` dan online, panggil `touch_activity` tiap 120 detik dan saat tab kembali visible. Tab tersembunyi tidak mengirim heartbeat. Hasil `IDLE`/`KICKED`/`LEFT` → tampilkan layar sesuai status.
- **Auto-kick idle**: member `APPROVED` dengan `last_active_at` lebih tua dari `idle_timeout_minutes` (default 30, pilihan Host 10–240) menjadi `IDLE`. Dijalankan cron tiap 5 menit **dan** secara lazy saat room penuh. Guest `IDLE` melihat "Kamu keluar otomatis karena tidak aktif" + tombol **Masuk lagi** (`rejoin_room`, tanpa mengetik password bila `password_version` tidak berubah). Host tidak pernah idle-kick.
- **Mengetik**:
  - Channel Broadcast **private** `typing:<room_id>`, event `typing`, payload `{ s: "<8 hex acak per tab>" }` (tanpa identitas member).
  - Pengirim: saat input berubah, kirim paling sering sekali per 5 detik. Berhenti kirim setelah tidak mengetik.
  - Penerima: hitung `s` unik dalam 6 detik terakhir → "Ada yang sedang mengetik…" / "N orang sedang mengetik…". Abaikan event dari diri sendiri.
  - Aktif jika `rooms.typing_enabled` **dan** `app_config.typing_global_enabled` (field `typing_effective`). Default `typing_enabled` = `max_guests <= 20`.
  - Biaya: satu event ≈ satu pesan chat dalam hitungan kuota. Batasi (throttle) dan jangan dikirim bila tidak ada orang lain di room.
  - Keterbatasan diterima: otorisasi channel private kemungkinan hanya dievaluasi saat join, jadi member yang baru dikeluarkan masih bisa menerima denyut "mengetik" sampai reconnect. Payload tidak berisi konten/identitas. Client wajib unsubscribe saat status bukan `APPROVED`. **Verifikasi perilaku ini di T-15/T-60.**
- **Multi-room tanpa login**: sesi anonim Supabase tersimpan di browser (`persistSession`). Halaman `/rooms` memakai `my_rooms()`. Penanda belum-dibaca disimpan di `localStorage` kunci `lastRead:<room_id>` (id pesan terakhir). Batasan yang harus ditampilkan di UI: data hilang jika storage dibersihkan, ganti perangkat, atau browser menghapus storage situs yang lama tidak dibuka (mis. Safari ±7 hari).

## 9. Lifecycle & cron (pg_cron)

| Job | Jadwal | Aksi |
|---|---|---|
| `release_idle_members()` | tiap 5 menit | APPROVED idle → `IDLE` |
| `expire_pending_members()` | tiap jam | PENDING > `pending_ttl_hours` → `LEFT` |
| `purge_join_attempts()` | tiap jam | hapus > 24 jam |
| `delete_expired_rooms()` | harian 20:00 UTC (03:00 WIB) | hapus room dengan `delete_at < now()` (cascade) |

Pelepasan kursi tidak bergantung pada cron karena juga dilakukan lazy. Akses sudah diblokir RLS meski cron gagal. Keep-alive: workflow `.github/workflows/keepalive.yml` memanggil `/api/health?db=1`.

## 10. Persyaratan keamanan dan tes wajib (dikerjakan S)

Semua harus **ditolak** / benar. Tulis sebagai skrip otomatis di `scripts/security/` dan tes SQL di `supabase/tests/security/`.

| ID | Uji | Hasil yang benar |
|---|---|---|
| S-01 | Host `PATCH /rest/v1/rooms` mengubah `expires_at`/`closed_at`/`max_guests` langsung | ditolak (tidak ada policy UPDATE) |
| S-02 | Host `INSERT` ke `rooms` langsung (lewati kuota) | ditolak |
| S-03 | Host mengubah `profiles.tier` sendiri | ditolak |
| S-04 | `send_message` dengan `sender_name:'Host'` atau parameter sender | parameter tidak ada; sender dari DB |
| S-05 | Guest room A membaca pesan room B (REST dan Realtime) | kosong / ditolak |
| S-06 | Guest `KICKED`/`IDLE`/`LEFT` memanggil `send_message` dan menerima event pesan baru | `NOT_MEMBER`; tidak menerima event |
| S-07 | JWT anonim memanggil `create_room` dan semua RPC Host | `NOT_HOST` |
| S-08 | `authenticated`/`anon` memanggil `join_room` | permission denied |
| S-09 | Host membaca `room_members` / `list_members` | tidak ada `user_id`; `member_identities` tidak terbaca |
| S-10 | Host membaca kolom `password_hash` | permission denied |
| S-11 | 6 percobaan password salah dari satu `ip_hash` | percobaan ke-6 → `LOCKED` |
| S-12 | Dua IPv6 dalam satu /64 | dihitung satu klien |
| S-13 | Membuka dua tab Host berbarengan saat kuota 2/3 | tepat satu room ke-3 berhasil |
| S-14 | Guest ke-N+1 saat kursi penuh; dua approve bersamaan | `ROOM_FULL`; tidak ada nomor ganda |
| S-15 | Query katalog: semua tabel `public` ber-RLS; semua fungsi `SECURITY DEFINER` punya `search_path`; tidak ada EXECUTE ke `PUBLIC`/`anon` selain yang dikontrak | lolos |
| S-16 | `grep` bundle client untuk `SERVICE_ROLE`, `TURNSTILE_SECRET`, `IP_HASH_SALT` | tidak ada |
| S-17 | Pesan `<img src=x onerror=...>` dan `javascript:` URL | tampil sebagai teks; tidak tereksekusi |
| S-18 | Header: `Referrer-Policy: no-referrer`, CSP, `X-Robots-Tag` di `/r/*` | ada |
| S-19 | Pesan setelah `closed_at`/`expires_at` | `ROOM_CLOSED` |
| S-20 | Akses room setelah `delete_at` walau cron belum jalan | ditolak RLS |

## 11. Halaman (agent F)

`/` landing · `/login`, `/register` (Host, Turnstile) · `/dashboard` (daftar room, sisa kuota, buat room) · `/dashboard/r/<id>` (ruang Host: chat + panel member Approve/Reject/Kick, ganti password, tutup, ekspor) · `/r/<slug>` (Guest: disclaimer → Turnstile → anonymous sign-in → password → status lobby/chat) · `/rooms` (Ruang saya) · `/privasi` dan `/batas-anonimitas`.

Keadaan Guest yang wajib ditangani: password salah, terkunci (tampilkan waktu tunggu), room penuh, menunggu persetujuan, ditolak, dikeluarkan, idle (tombol Masuk lagi), room ditutup, maksimum 5 room.
Form buat room: nama, kapasitas (slider 2…cap tier, tampilkan cap), approval, timeout idle (10/30/60/120/240 menit), toggle mengetik (default sesuai `max_guests`). Saat kuota habis tampilkan "Batas room aktif tercapai (3/3)" tanpa tombol bayar.
Ekspor `.txt` dibuat di browser dari `export_messages` berhalaman. Baris: `[DD-MM-YYYY HH:MM] Guest-01: isi` (WIB, `Asia/Jakarta`), header nama room + waktu ekspor; baris lanjutan diberi indentasi.
Desain: pakai `design/tokens.css` (sementara; token Figma menyusul di T-30). Tema terpilih: DNA template **Stiker bawaan** situs utama (mint `#DFF2EC→#BFE5DA`, ink `#1F4D46`, aksen koral `#E8604C`, panel kaca miring) — dipilih manusia 2026-10-28; palet kaca-blush sudah dipakai subsite form. Kerangka UI statis (T-31) sudah dikerjakan; keadaan Guest dapat dipratinjau lewat query `?state=…` di `/r/<slug>`.

## 12. Environment

`PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `PUBLIC_TURNSTILE_SITE_KEY` (publik) · `SUPABASE_SERVICE_ROLE_KEY`, `TURNSTILE_SECRET_KEY`, `IP_HASH_SALT` (≥ 32 karakter, rahasia). Skema dideklarasikan di `astro.config.mjs` (`astro:env`). Runtime Node ≥ 22.22 (atur di Vercel).

## 13. Di luar scope MVP

Pembayaran/langganan aktif, Cloudflare proxy, co-host, edit/hapus pesan, file/media, E2EE, presence "siapa online", nama pengetik, notifikasi push/email, laporan penyalahgunaan ke admin platform, penautan akun Guest antar-perangkat.

## 14. Pertanyaan terbuka (default dipakai sampai manusia memutuskan)

1. Angka kuota/kapasitas tier (bagian 3) dan nilai premium.
2. D-13: Guest kehilangan akses total setelah CLOSED.
3. Supabase: akun/proyek baru terpisah (default).
4. Konfirmasi email Host aktif? (SMTP bawaan Supabase terbatas.) Default: aktif.
5. Google OAuth untuk Host: fase berikutnya.
6. Nama produk dan subdomain final.
