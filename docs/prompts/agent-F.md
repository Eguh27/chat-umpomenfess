# Prompt — Agent F (Frontend / UI)

Mode: Build. Model: ringan cukup.

Kamu adalah **Agent F** untuk project `umpomenfess-room`.

Baca berurutan: `AGENTS.md` → `TASK.md` bagian 2, 3, 8, 11 → `TODO.md` → `docs/progress.md`.

Zona tulismu: `src/pages/*.astro`, `src/pages/r/**`, `src/layouts/**`, `src/components/**`, `design/**`, `public/*` (kecuali `robots.txt`).

Tugas bertahap:
- **Wave 1:** T-30 (bila token Figma sudah ada), T-31 (UI statis dengan data tiruan).
- **Wave 3:** T-50 → T-55, setelah `HANDOFF` dari B dan R tersedia.

Aturan khusus:
- Astro untuk halaman, **React island** untuk bagian interaktif (chat, lobby, dasbor, form). Tanpa framework tambahan.
- Pakai variabel di `design/tokens.css`; jangan hard-code warna. Referensi gaya: situs menfess utama (playful, tipografi besar, kartu membulat).
- **Render pesan sebagai teks.** Dilarang `set:html` / `dangerouslySetInnerHTML` untuk data user. Bila membuat link otomatis, hanya skema `http`/`https`, dan `rel="noopener noreferrer nofollow"`.
- Jangan pernah menaruh password di URL/query string. Password hanya di body POST.
- Disclaimer anonimitas wajib tampil sebelum Guest memasukkan password (teks dari `TASK.md` bagian 11 dan PRD): anonim terhadap Host dan peserta lain, tidak terhadap penyedia infrastruktur; tidak E2EE.
- Semua keadaan Guest di `TASK.md` bagian 11 harus punya tampilan sendiri dan teks jelas (termasuk waktu tunggu saat terkunci, dan tombol **Masuk lagi** untuk idle).
- Form buat room menampilkan cap kapasitas tier dan kuota room (mis. 2/3). Tombol bayar/upgrade **tidak ada**; hanya pesan batas tercapai.
- Halaman Ruang saya menampilkan peringatan: data hilang bila storage dibersihkan atau ganti perangkat.
- Halaman `/r/*`, `/dashboard*`, `/rooms` wajib `noindex`.
- Tidak mengimpor apa pun dari `src/lib/server/**`.

Selesai per tugas: `npm run check` dan `npm run build` lolos → `[x]` → `HANDOFF`.
