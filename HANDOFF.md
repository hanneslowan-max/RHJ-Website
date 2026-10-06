# Serah-terima sesi — revisi 29–49 (SELESAI di branch, sudah diverifikasi)

Baca dulu `ATURAN.md` (aturan kerja: uji tabrakan dulu, lapor + rekomendasi, Hannes memutuskan).

## Sesi EHC & komisi (branch `claude/bold-bardeen-5r2fg8`, mulai 6 Okt 2026) — SEDANG BERJALAN

### Koordinasi dengan sesi lain (disetujui Hannes 6 Okt)
- Sesi "Lanjut revisi 50–61" (branch `claude/gracious-carson-f61fhq`) mengerjakan 50–53 dan 55–60.
  **#54 dan #61 dipindah ke sesi EHC & komisi.**
- Nomor migrasi: sesi 50–61 memakai **db/120–139**; sesi EHC & komisi memakai **db/140 ke atas**.
  DEV sudah menjalankan s.d. 119 (118 Ahen→Hendri, 119 pelanggan sales nonaktif + Office tanpa komisi —
  keduanya dari sesi 50–61). Draf `db/118-perbaikan-audit-keamanan.sql` di branch `claude/epic-maxwell-61a99g`
  belum dijalankan dan nomornya sudah terpakai — beri nomor baru bila dipakai.
- Sebelum `create or replace` fungsi apa pun, bandingkan dulu dengan definisi terbaru di DEV
  (`pg_get_functiondef`) — sesi lain mungkin sudah mengubahnya. Bangun di atas versi DEV, jangan menimpa.
- Objek yang dipegang sesi EHC & komisi: tabel `ehc_klaim*`, `komisi_klaim*`, `ehc_cepat_log`,
  `transfer_pengajuan*`, `transfer_batch`, view `ehc_belum_klaim`, `kas_sales`, `ehc_cepat_siap`, RPC klaim
  EHC/komisi/cepat/transfer, policy storage `rhj_ehc_bukti_*`/`rhj_komisi_bukti_*`; untuk #54 juga
  `jaga_baris_sp_terkunci`, `sp_vonny_gugur_baris` (ehc_item), usul ubah/`putuskan_ubah`, `gm_konteks_keputusan`.
  Rumus komisi (`so_baris_hitung`, `komisi_tier`, `komisi_hitung`) **tidak** diubah.

### Keputusan Hannes — struktur EHC (6 Okt)
- EHC = budget entertain customer yang disisihkan di SP; akun terpisah dari penjualan.
- **Untuk apa:** (1) transfer langsung ke customer, (2) entertain (makan, ngopi, parcel, dll.), (3) ongkos bongkar
  muat di gudang customer. **Cara bayar:** (1) transfer langsung ke customer, (2) kartu kredit perusahaan,
  (3) sales bayar dulu → reimburse.
- **EHC per SP = saldo.** Boleh dipakai berkali-kali lintas bulan selama komisi SP itu belum diklaim. Satu transaksi
  boleh memotong beberapa SP (tiap SP maksimal sisa saldonya). Begitu komisi SP diklaim, EHC-nya tertutup dan sisa
  saldo otomatis masuk **kas sales**. Sebelum klaim komisi, sales diberi peringatan sisa EHC yang akan pindah.
- Setiap pemakaian menunjuk SP asal; penerimanya customer SP itu. **Untuk customer lain wajib persetujuan GM.**
- Sales menyetor pemakaian kapan saja (dicicil): nominal, untuk apa, cara bayar, SP, **lampiran wajib** (bill /
  bukti transfer) — mengubah ATURAN B "klaim EHC tidak memerlukan lampiran".
- **Periode EHC:** setoran tgl 19 bulan lalu s/d tgl 18 bulan ini (WIB) = periode bulan ini; sesudah tgl 18 →
  bulan berikutnya. Sesudah cutoff 18 **GM memeriksa dulu**, baru finance memproses **tgl 20**.
- Entertain boleh sebelum customer bayar, tetapi **reimburse dan transfer ke customer baru diproses sesudah SP lunas**.
- **Kartu kredit perusahaan:** finance (peran `finance`, akun orangnya belum ada di DEV) memasukkan baris statement
  (tanggal, merchant, nominal); sales menunjuk SP + untuk apa + lampiran bill. Tidak menunggu SP lunas.
- Setoran ditolak GM → kartu kredit: **dipotong dari komisi** sales itu yang berikutnya (kurang → terbawa ke
  bulan berikutnya, tercatat sebagai utang sales); reimburse: tidak diganti, saldo SP kembali.
  Saldo SP kurang: transfer/reimburse ditolak sistem (tambah SP); kartu kredit → kekurangannya dipotong dari komisi.
- **EHC cepat + EHC dini digabung jadi satu fitur "EHC cepat" (darurat):** cair segera di luar jadwal, boleh
  sebelum SP lunas, wajib alasan + lampiran + persetujuan GM per transaksi.
- Data klaim EHC lama di DEV hanya latihan; migrasi tetap memindahkannya ke format baru (tidak dihapus).

### Keputusan Hannes — struktur komisi (6 Okt)
- Alur sama dengan EHC, tetapi uangnya ke rekening sales sendiri (rekening diisi finance).
- **Periode komisi:** tgl 24 s/d **cutoff tgl 23**, GM memeriksa, finance transfer **tgl 25**.
- Nominal tetap **dihitung sistem** (tier price list, flat 1% Riksa/Michael, >120 hari persen GM, Office 0% dari
  berkas 119). Satu SP satu klaim, sesudah lunas. **Tanpa lampiran.**
- **Transfer terpisah:** EHC (reimburse) tgl 20; komisi tgl 25 dikurangi potongan kartu kredit.
- #61: sebelum cutoff, pemakaian EHC masih bisa diubah dan klaim komisi bisa diubah/cancel.
- #54: sales boleh minta tambah/ubah EHC di SP di tahap mana pun selama komisi SP belum diklaim; lewat approval
  GM, dan GM memilih persen komisi diubah atau tetap.

### Rencana tahap
1. Pemakaian EHC (multi per SP, alokasi ke beberapa SP, untuk apa, cara bayar, lampiran wajib, customer lain → GM,
   saldo per SP). 2. Kartu kredit (input statement finance, potongan komisi). 3. Periode & pemeriksaan GM EHC
   (cutoff 18, proses 20, tunggu lunas, EHC cepat). 4. Komisi (cutoff 23, transfer 25, potongan, tutup EHC → kas
   sales, #61). 5. #54 edit EHC di SP. 6. Laporan finance.

### Posisi tahap 1 (6 Okt sore)
- **Kode selesai, BELUM dijalankan di DEV**: `db/140-ehc-saldo-pemakaian.sql` (masih bertanda DRAF), `db/140b-…`
  (DROP manual), layar EHC/Kas/Laporan Finance/peringatan komisi di index.html, ATURAN B bagian "EHC".
- Rancangan diuji adversarial (4 sudut + pembantah); semua temuan berat sudah masuk 140.
- Uji layar Playwright (Supabase dicegat, tanpa request keluar): **14/14 lulus**, desktop & 390px. Harness di
  scratchpad sesi (`layar/run.js`), tidak ikut repo.
- **Uji DB dalam transaksi rollback belum bisa jalan**:
  1. MCP Supabase macet (timeout 60 dtk, menunggu konfirmasi yang tidak muncul) untuk DROP **dan untuk fungsi yang
     badannya memuat DELETE dengan syarat nyata**. 140 sudah ditulis ulang tanpa DELETE: lampiran dibuang = ditandai
     `dibuang_pada`; SP yang dilepas saat klaim diubah = alokasi nominal 0; pengajuan transfer kosong tidak dibuat.
     Skrip uji (scratchpad `uji/uji1.py` → `uji1.sql`, ±45 skenario per peran) juga sudah bebas DELETE.
  2. Sejak ±sore konektor Supabase menjawab `FGA Authentication Error. Unauthorized` untuk semua perintah —
     perlu Hannes menyambungkan ulang konektor Supabase.
- Langkah berikut begitu konektor pulih: jalankan `uji1.sql` (rollback) → perbaiki bila ada yang gagal →
  `apply_migration` 140 ke DEV → Hannes menjalankan 140b di SQL Editor DEV → uji multi-klaim per SP & reimburse →
  hapus tanda DRAF → commit.

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

## Langkah berikut
1. Hannes mencoba di DEV. Setelah Hannes mengetik "revisi selesai" → jalankan verifikator.
2. PR ke `main` hanya bila Hannes meminta. Migrasi 109–114 belum pernah dijalankan di PROD.
