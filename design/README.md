# Design system — umpomenfess room

Arah: **Stiker Tempel** — papan mint dengan panel kaca miring ala stiker
tempelan. Palet diambil dari template **Stiker BAWAAN** situs utama
(`umpomenfess/src/styles/templates.css`, `.tpl-stiker`, tanpa preset), bukan
dari preset lain. Catatan: subsite `form.umpomenfess.my.id` sudah memakai
tema **Kaca · Blush**; project ini sengaja berganti ke Stiker bawaan agar
tiap subdomain punya wajah sendiri tapi tetap satu keluarga DNA (Baloo 2 +
Quicksand, koral, teal).

File token: [`tokens.css`](./tokens.css). Semua halaman memakai token ini;
jangan menulis warna atau ukuran font mentah di komponen.

## Palet

| Token | Nilai | Dipakai untuk |
|---|---|---|
| `--mint-1` / `--mint-2` | `#DFF2EC` / `#BFE5DA` | gradasi latar halaman (st1/st2 bawaan) |
| `--ink` / `--ink-soft` | `#1F4D46` / `#35655A` | teks utama & sekunder (8.17 / 4.88 di mint) |
| `--surface` / `--paper` | `#FFFFFF` / `#FBF3E4` | kartu solid & kartu foto (DNA stiker) |
| `--surface-glass` | `rgba(255,255,255,.55)` | panel kaca miring (DNA st-glass) |
| `--coral` / `--coral-strong` | `#E8604C` / `#B8422E` | stiker & ikon / tombol-CTA (5.44 w/ putih) |
| `--teal` / `--teal-strong` / `--teal-deep` | `#3D8A7C` / `#2A6053` / `#24574D` | dekorasi tag / link & CTA sekunder / bubble Host |
| `--orange` / `--gold` | `#F5A54B` / `#F6C96B` | stiker chat / stiker percik & badge PENDING |

`--teal #3D8A7C` hanya untuk teks besar/dekorasi (4.10 di putih) — teks
kecil memakai `--teal-strong` (7.25) atau `--teal-deep` (8.25).

Bentuk: panel kaca **26px miring 1,6°** (DNA), kartu & input **10–16px**,
pill **999px**. Bayangan `--shadow` 20/44, `--shadow-sm` 8/20,
`--shadow-sticker` 4/10. Garis pemisah memakai **putus-putus**
(`--border-dash`) ala alat tulis; tidak ada grain.

Tipografi:

- **Baloo 2** 500–700 — judul, brand, tombol.
- **Quicksand** 400–700 — isi & UI.
- **Space Mono** 700 — password room & angka hitung-downtime.

## Struktur stylesheet

- `design/tokens.css` — token murni, tanpa selektor komponen.
- `design/base.css` — reset, latar, skip-link, header/footer disuntik
  lewat komponen, tombol, form, kartu, badge, util layout.
- `design/chat.css` — gelembung chat, indikator mengetik, composer, panel
  member (dipakai `/r/*` dan `/dashboard/r/*`, juga pratinjau landing).
- Komponen: `SiteHeader.astro`, `SiteFooter.astro`,
  `StickerDecor.astro` (SVG stiker: chat, surat, foto, percik — 1:1 dari
  `render.ts` situs utama), `mockData.ts`.

## Keputusan desain

- **Tidak ada dark mode.** DNA stiker adalah latar terang; dua mode berarti
  menjaga kontras 2× untuk palet pastel ini. Bila kelak diminta, token
  verde-invert menyusul lewat ekspor Figma (T-30).
- **Koral hanya satu aksen.** Elemen besar/dekorasi boleh `--coral`;
  tombol & teks aksen wajib `--coral-strong` (kontras ≥4.5).
- **Stiker dari DNA, bukan emoji.** Aset SVG meniru
  `src/lib/templates/render.ts` situs utama (chat, surat, foto, percik).
- Panel kaca miring **hanya untuk panel showcase/dekoratif**; konten
  fungsional (chat, form, daftar) tetap lurus agar nyaman dibaca.

## Kontras (verifikasi)

Hasil hitung WCAG untuk pasangan yang dipakai:
ink/mint-1 8.17 · ink/mint-2 6.99 · muted/mint-2 4.88 · muted/putih 6.05 ·
krem/coral-strong 5.09 (putih 5.44) · krem/teal-deep 7.71 · ink/gold 6.11 ·
teal-strong/putih 7.25 · teal-deep/putih 8.25.
