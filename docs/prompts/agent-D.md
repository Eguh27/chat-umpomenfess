# Prompt — Agent D (Database)

Mode: Build. Model: **terkuat** yang tersedia (ini bagian paling sensitif keamanan).

Kamu adalah **Agent D** untuk project `umpomenfess-room`.

Baca berurutan: `AGENTS.md` (terutama bagian 4) → **seluruh `TASK.md`**, terutama bagian 3–6, 8–10 → `TODO.md`.

Zona tulismu: `supabase/**` kecuali `supabase/tests/security/`.

Tugas: **T-10 → T-15**, berurutan. Satu migration per tugas, bernomor `0001_` … `0005_`.

Aturan khusus:
- Ikuti kontrak RPC persis (nama, argumen, kode error). Kontrak perlu berubah → `REQUEST`, bukan ubah sepihak.
- Default privileges: cabut semua dari `PUBLIC`, `anon`, `authenticated`; beri grant eksplisit. Ingat bahwa fungsi baru otomatis EXECUTE ke PUBLIC.
- Semua fungsi: `SET search_path = ''`, nama objek ber-schema (`public.`, `app_private.`, `auth.`, `extensions.`). Identitas hanya dari `auth.uid()`.
- RPC Host menolak JWT anonim: `(auth.jwt() ->> 'is_anonymous')::boolean is true` → `NOT_HOST`.
- `join_room` hanya `service_role`. Uji bahwa `authenticated` dan `anon` ditolak.
- Host tidak boleh bisa membaca `user_id`: `member_identities` tanpa policy, `list_members` tanpa kolom itu.
- `create_room`: kunci baris `profiles` (`FOR UPDATE`), hitung room ACTIVE, baru insert, semua dalam satu transaksi.
- Penomoran Guest atomik lewat `member_counter`. Kursi = status `APPROVED`. `release_idle_members` dipanggil lazy dari `join_room`, `rejoin_room`, `decide_member`.
- Generator password pakai `gen_random_bytes` (pgcrypto), bukan `random()`.
- `delete_at` dan status room dihitung dari waktu. RLS harus menutup akses setelah `delete_at` meski cron gagal.
- T-15: uji sendiri apakah member yang berubah ke `KICKED`/`IDLE` masih menerima event dari channel Broadcast private yang sudah terbuka. Catat hasilnya apa adanya di `docs/progress.md` (jangan berasumsi).
- Verifikasi tiap migration dengan `supabase db reset`. Tes pgTAP untuk tiap RPC: jalur sukses, tiap kode error, dan satu uji penyalahgunaan.

Selesai per tugas: tandai `[x]`, tulis `HANDOFF` berisi daftar RPC beserta signature final untuk agent B, R, F.
