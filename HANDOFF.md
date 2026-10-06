# Serah-terima sesi — revisi 29–49 (SELESAI di branch, sudah diverifikasi)

Baca dulu `ATURAN.md` (aturan kerja: uji tabrakan dulu, lapor + rekomendasi, Hannes memutuskan).

## Status
- Revisi 1–28 selesai. 1–27 sudah di `main` (PR #1). #28 + `ATURAN.md` ada di branch `claude/perbaikan-revisi-27`.
- **Revisi 29–49 selesai dikerjakan** di branch `claude/nice-cray-21r8g4` (belum di-merge, belum ada PR).
- **Verifikator menyeluruh sudah dijalankan** (atas permintaan Hannes, multi-agent: 4 pemeriksa per area + skeptis
  per area + kritik kelengkapan). 26 temuan terkonfirmasi (±19 unik, 0 dibantah) — semuanya diperbaiki di
  `db/115` + index.html, diuji ulang. Belum diperiksa verifikator: #46 (tidak tereproduksi), kegagalan di tengah
  simpanPo sesudah pelanggan baru dibuat (pola lama: kepala & baris PO dikirim terpisah), ganti set master↔inline.
- DB DEV (`eesdtbcualkdawhykchj`) sudah menjalankan migrasi sampai `db/115` (+ perbaikan `114b`, isinya sudah
  ada di berkas 114). PROD (`hyjiuefqnsrofpebaydt`) TIDAK disentuh sama sekali.
- Uji: tiap migrasi diuji dulu dalam transaksi yang dibatalkan (simulasi peran lewat `request.jwt.claims` +
  `set local role authenticated`). Migrasi yang mengubah view/rumus (110, 113, 114) dibuktikan tidak mengubah
  angka data lama dengan sidik md5 view/laporan sebelum = sesudah. Uji layar: harness Playwright (Supabase
  dicegat, tidak ada request keluar) — 101/101 lulus sesudah perbaikan verifikator. Harness ada di scratchpad sesi (tidak ikut repo).

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
| verifikator | PO wajib pelanggan; lampiran PO (policy lama, pemilik berkas); lengkapi pelanggan SP (HP, lintas sales); hapus produk (set inline/usulan); spesifikasi = master tidak dicatat; mode SP ber-invoice terkunci; laporan per produk dari DPP; qty pecahan; harga otomatis include ×1,11; cari "osaka" | 115 |

## Catatan untuk Hannes (perlu diketahui / dikonfirmasi)
- **#30 turunan:** pada mode Include, harga nett & EHC di SP dianggap termasuk PPN; price list, tier komisi,
  harga khusus, margin, dan nilai EHC dihitung dari DPP (÷ 1,11). Ini supaya aturan komisi tidak bergeser
  (price list memang tanpa PPN). Contoh: PO 3 × 111.000 include → komisi dari 300.000 (tier 2%), bukan 5%.
  Harga khusus yang diajukan dari SP include disimpan dalam DPP, dipotong ke sen di bawahnya.
- **#30:** mode PPN PO maupun SP tidak bisa diubah bila SP-nya sudah ber-invoice (ditolak dengan pesan).
- **Include, harga otomatis:** isian dari price list = list × 1,11, dinaikkan ke sen berikutnya bila tidak habis
  (hanya usulan isian; umumnya list ribuan bulat → persis, mis. 99.900 → 110.889).
- **#37:** SP 032 (sales Ahen) cocok nama dengan pelanggan milik Hendri (nonaktif) → kini ditolak saat cek Vonny
  sampai owner/GM memindahkan pelanggannya atau mengganti sales SP.
- **#46:** kegagalan persisnya tidak bisa direproduksi (RPC & layar jalan untuk sales/Vonny/owner, desktop & HP).
  Yang ditemukan & diperbaiki: pelanggan baru tidak bisa (#41), price list terpotong 1.000 baris, format angka
  saat mengetik dengan keyboard HP (IME), klik pertama Submit/Simpan hilang sesudah mengetik. Kalau masih gagal,
  minta teks pesan galatnya.
- **#49:** tabel pelanggan tidak punya kolom kota — yang ditampilkan "cabang".
- Data lama: sebagian nama `kepada` SP/PO lama masih berbentuk "NAMA, PT" (teks tersimpan); penawaran baru
  mengambil nama rapi dari data pelanggan.
- Insiden kecil DEV: versi pertama trigger `sinkron_mode_ppn` (114) menggagalkan insert PO beberapa menit
  (PL/pgSQL tidak memotong AND pada `new.po_id`). Diperbaiki di 114b; tidak ada data yang berubah/hilang.

## Sesudah revisi 49 (data & perbaikan)
| Isi | Migrasi |
|---|---|
| Tab Pelanggan timeout — RLS fungsi peran dihitung sekali per query + indeks urut | 116, 116b |
| Pelanggan Hendri (id 15) dipindah ke akun sales id 1 (orang yang sama) | 117 |
| Sales id 1 "Ahen" diganti nama jadi **"Hendri"** (akun Hendri Pratomo; login, 432 pelanggan, 3 PO, 3 SP, 16 lead tetap); sales lama id 15 jadi "Hendri (lama)"; tautan sheet 15 → 1 | 118 |
| Pelanggan sales nonaktif dilepas (209 di DEV: Yohannes 81, Ryanto 57, Gugie 32, Hasan 17, Gandha 11, William 9, Andi 2) + `sales_rep_lama_id` + trigger saat sales dinonaktifkan; Office: SP hanya GM/owner (`sales_reps.sp_hanya_gm`, trigger `so_y_hanya_gm`), komisi flat 0%. FE: Office disembunyikan dari kotak Sales SP & simpan dikunci untuk selain GM/owner; tab Pelanggan menampilkan "sales lama (nonaktif)" | 119 |

- Draf lama di branch `claude/pelanggan-nonaktif-office` sudah digantikan `db/119` di branch ini (branch itu boleh dihapus).
- Uji 119: DB dalam transaksi yang dibatalkan (simulasi sales, staff, GM, owner) + layar Playwright 36/36
  (staff & GM di desktop dan HP 390px, mode "Dari PO" Office, tab Pelanggan, DB tanpa kolom baru). Ketujuh sales nonaktif tidak punya
  PO/SP/penawaran/lead; Office belum punya SP/klaim komisi → tidak ada angka lama yang bergeser.
- **Catatan alat:** perintah `DROP …` lewat MCP Supabase menunggu konfirmasi "destruktif" yang tidak muncul di
  sesi ini lalu timeout 60 detik (transaksinya batal, tidak ada yang berubah). Pakai `create or replace trigger`
  (PG 17) — jangan `drop trigger if exists` + `create trigger`.
- **Perlu keputusan Hannes:** pelanggan belum bertuan hanya diklaim lewat **PO** (jalur lama, berkas 79) —
  penawaran dan SP tanpa PO tidak mengklaim. Ini berlaku juga untuk ±2.470 pelanggan lain yang belum bertuan.
  Bila "memakai" juga berarti membuat penawaran, perlu revisi terpisah.

## Revisi 50–61 (sedang dikerjakan)
Uji tabrakan sudah dijalankan untuk semua (workflow 12 penyelidik + 12 pemeriksa skeptis, read-only, 6 Okt).
Nomor migrasi sesi ini: **db/120–139**. Sesi lain "Revisi klaim EHC dan komisi" (branch `claude/bold-bardeen-5r2fg8`)
memakai **db/140+** dan mengusulkan mengambil **#54 & #61** — menunggu konfirmasi Hannes di sesi ini. Sesi itu minta
kabar (send_message ke session_01AWPMAWgbLCoULbHsRgrHzj) sebelum objek berikut di-create-or-replace: klaim EHC/komisi &
transfer, `jaga_baris_sp_terkunci`, `sp_vonny_gugur_*`, `putuskan_ubah`, `gm_konteks_keputusan`,
`batalkan_baris_sp`/`pulihkan_baris_sp`, `jaga_rekening_pic`, `laporan_komisi`. Rumus komisi (`so_baris_hitung`,
`komisi_tier`, `komisi_hitung`) tidak diubah sesi itu.

| # | Ringkas | Status |
|---|---|---|
| 50 | Cek Vonny: layar memanggil `lengkapi_pelanggan_sp` dulu; bila ditolak (HP kosong/format/bentrok, nama milik sales lain) `putuskan_vonny_cek` tak pernah dipanggil → SP tetap di Double Check (log DEV 2 Okt) | tanya: lolos tanpa tautan utk kasus HP; HP wajib di form SP |
| 51 | Form SP tidak menampilkan komisi; sales baru lihat di tab Komisi › Belum bisa klaim. Bug: `gm_pct` utk baris di bawah list diabaikan bila SP tidak telat (SP 007/010/011/015-IX: komisi 0) | tanya: maksud "tampilkan"? perbaiki gm_pct? |
| 52 | Cache per tab tidak pernah dimuat ulang (pindahTab hanya menggambar ulang) | dikerjakan (tanpa polling) |
| 53 | DEV sudah "RHAJA Series" (59 produk, 1 Sep); 27 produk kehilangan bacaan bahan | tanya: layar mana (PROD vs tipe roda "+ Set") |
| 54 | → sesi EHC/komisi (menunggu konfirmasi) | — |
| 55 | Belum ada unduh/cetak penawaran untuk peran apa pun | tanya: isi kop/penutup, logo |
| 56 | Spesifikasi sudah ada di form; di dokumen hanya teks kecil di bawah kode, input 1 baris | dikerjakan |
| 57 | Set dipecah per pcs di SP sesuai ATURAN; usul tampilan berkelompok + kolom penanda set | tanya: "set (sudah diubah)" & kunci qty |
| 58 | Indo Kida (Iwan, 2604) vs Garuda Metalindo (Hendri, 2354) — menabrak #48 | tanya: opsi A ganti nama / B induk / C gabung |
| 59 | DB sudah dukung usulan produk dari penawaran; form tidak menampilkan "+ item baru" | inti dikerjakan; tanya: "Buang" usulan |
| 60 | UP, e-mail, diskon, TOP belum ada | tanya: bentuk diskon/TOP/UP |
| 61 | → sesi EHC/komisi (menunggu konfirmasi) | — |

## Temuan keamanan & bug — DIKERJAKAN DI AKHIR (keputusan Hannes 6 Okt)
Dari uji 50–61 (terbukti di DEV dalam transaksi yang dibatalkan):
1. **Komisi terbaca lewat REST oleh peran yang layarnya menyembunyikan**: Vonny membaca `so_ringkas.komisi` 54 SP
   (Rp 18.550.689,70) dan `komisi_belum_klaim` 51 baris; kemungkinan juga Lie Sian/Ichi/Lenni.
2. **Nama pelanggan ganda**: sales bisa PATCH nama pelanggannya jadi persis nama pelanggan sales lain, dan POST
   `/customers` dengan nama ganda lolos (hanya `buat_pelanggan_baru` yang menolak). Uji: Iwan → "PT Garuda Metalindo".
3. **View `usulan_produk`** (milik postgres, bukan security_invoker): semua sales membaca seluruh usulan, pembuatnya,
   dan customer PO sales lain.
4. **`quote_lines` tanpa penjaga baris**: INSERT teks bebas (tanpa product/set) lewat REST lolos — `jaga_jenis_baris`
   tidak terpasang (butuh fungsi baru; quote_lines tidak punya kolom jenis).
5. **Total SP lunas bisa naik**: GM bisa PATCH `sales_order_lines.ehc_item` SP tanpa PO yang sudah ber-invoice/lunas
   (SP 150: 1.640.000 → 1.740.000) — `periksa_total_sp` keluar bila SP tanpa PO. (Area #54 — sesi EHC.)
6. **Klaim EHC/komisi** (area #61 — sesi EHC): owner/GM/staff/finance bisa ubah nominal lewat REST
   (`ekn_ubah`/`kkn_ubah`) tanpa hitung ulang kas; owner bisa hapus klaim yang sudah diajukan/ber-batch (langsung
   atau cascade hapus SP); klaim tidak ikut berubah bila EHC SP diubah (SP 007-IX: klaim 20.000, EHC jadi 5.000).
7. **Daftar hitam terlewati** pada SP tanpa PO tanpa pelanggan (`jaga_blacklist_po` hanya di PO) — makin sering bila
   #50 meloloskan SP tanpa tautan.

Bug/data non-keamanan yang dicatat:
- `putuskan_ubah` (Minta ubah SP) menghapus & membuat ulang semua baris → gagal pada SP yang sudah punya surat jalan
  bertahap / qty batal (SP 159). (Area #54.)
- Jalur cek Vonny di laci Pengiriman (`formKirim`, ±index.html:10979) memanggil `lengkapi_pelanggan_sp` tanpa kotak
  HP/alamat — praktis tak terjangkau.
- Data DEV: pelanggan 5413 "BP. Nanang" (Alfred) ber-HP 622134567 = nomor isian Vonny; PT Shidachi Indo Jaya
  (Hendri) dijual Menik di SP 017/MCE/X.

## Langkah berikut
1. Hannes mencoba di DEV. Setelah Hannes mengetik "revisi selesai" → jalankan verifikator.
2. PR ke `main` hanya bila Hannes meminta. Migrasi 109–114 belum pernah dijalankan di PROD.
