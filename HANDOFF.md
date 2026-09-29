# Serah-terima sesi — revisi 29–49 (SELESAI di branch, belum diverifikasi)

Baca dulu `ATURAN.md` (aturan kerja: uji tabrakan dulu, lapor + rekomendasi, Hannes memutuskan).

## Status
- Revisi 1–28 selesai. 1–27 sudah di `main` (PR #1). #28 + `ATURAN.md` ada di branch `claude/perbaikan-revisi-27`.
- **Revisi 29–49 selesai dikerjakan** di branch `claude/nice-cray-21r8g4` (belum di-merge, belum ada PR).
  Verifikator BELUM dijalankan — menunggu Hannes mengetik "revisi selesai".
- DB DEV (`eesdtbcualkdawhykchj`) sudah menjalankan migrasi sampai `db/114` (+ perbaikan `114b`, isinya sudah
  ada di berkas 114). PROD (`hyjiuefqnsrofpebaydt`) TIDAK disentuh sama sekali.
- Uji: tiap migrasi diuji dulu dalam transaksi yang dibatalkan (simulasi peran lewat `request.jwt.claims` +
  `set local role authenticated`). Migrasi yang mengubah view/rumus (110, 113, 114) dibuktikan tidak mengubah
  angka data lama dengan sidik md5 view/laporan sebelum = sesudah. Uji layar: harness Playwright (Supabase
  dicegat, tidak ada request keluar) — 86/86 lulus. Harness ada di scratchpad sesi (tidak ikut repo).

## Revisi & migrasi
| Revisi | Isi | Migrasi |
|---|---|---|
| 39–48 | Penawaran: pelanggan baru (#41), pratinjau (#39), ganti item (#43), salin penawaran lama (#44), titik ribuan (#45), PT di depan (#47), sales lain ditolak tegas (#48), mode PPN (#42), spesifikasi master + "terakhir sales" (#40), sebab input gagal (#46) | 109 |
| 31 32 33 | Cari produk di semua kolom (brand/kelompok/kategori), hapus produk (permanen bila belum dipakai, selain itu nonaktif), alasan GM "Belum ada price list" vs "di bawah list" | 110 |
| 49 | Daftar baca-saja pelanggan sales lain (nama, cabang, industri, sales) | 111 |
| 35 36 37 38 | Double Check: menunggu / ditahan / baru diloloskan; tanda "baru lolos cek Vonny" di Pengiriman; lampiran PO (unggah + lihat); kategori untuk SP tanpa pelanggan master | 112 |
| 29 | Pelanggan baru di form PO tersimpan ke data pelanggan (nama, alamat, HP, sales PIC) | (pakai 109) |
| 34 | Total baris PO bisa diubah → penyesuaian pembulatan ±Rp 1.000/baris | 113 |
| 30 42 | Mode PPN Exclude/Include/Non-PPN di PO & SP; SP ikut PO | 114, 114b |

## Catatan untuk Hannes (perlu diketahui / dikonfirmasi)
- **#30 turunan:** pada mode Include, harga nett & EHC di SP dianggap termasuk PPN; price list, tier komisi,
  harga khusus, margin, dan nilai EHC dihitung dari DPP (÷ 1,11). Ini supaya aturan komisi tidak bergeser
  (price list memang tanpa PPN). Contoh: PO 3 × 111.000 include → komisi dari 300.000 (tier 2%), bukan 5%.
  Harga khusus yang diajukan dari SP include disimpan dalam DPP, dipotong ke sen di bawahnya.
- **#30:** mode PPN PO tidak bisa diubah bila SP-nya sudah ber-invoice (ditolak dengan pesan).
- **#46:** kegagalan persisnya tidak bisa direproduksi (RPC & layar jalan untuk sales/Vonny/owner, desktop & HP).
  Yang ditemukan & diperbaiki: pelanggan baru tidak bisa (#41), price list terpotong 1.000 baris, format angka
  saat mengetik dengan keyboard HP (IME), klik pertama Submit/Simpan hilang sesudah mengetik. Kalau masih gagal,
  minta teks pesan galatnya.
- **#49:** tabel pelanggan tidak punya kolom kota — yang ditampilkan "cabang".
- Data lama: sebagian nama `kepada` SP/PO lama masih berbentuk "NAMA, PT" (teks tersimpan); penawaran baru
  mengambil nama rapi dari data pelanggan.
- Insiden kecil DEV: versi pertama trigger `sinkron_mode_ppn` (114) menggagalkan insert PO beberapa menit
  (PL/pgSQL tidak memotong AND pada `new.po_id`). Diperbaiki di 114b; tidak ada data yang berubah/hilang.

## Langkah berikut
1. Hannes mencoba di DEV. Setelah Hannes mengetik "revisi selesai" → jalankan verifikator.
2. PR ke `main` hanya bila Hannes meminta. Migrasi 109–114 belum pernah dijalankan di PROD.
