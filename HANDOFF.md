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

- **DEV sudah menjalankan `140_ehc_saldo_pemakaian` dari sesi EHC/komisi** (6 Okt, bukan dari branch ini). Versi 140
  kini berlaku untuk `batalkan_baris_sp`, `pulihkan_baris_sp`, `jaga_rekening_pic`, `jaga_gerbang_klaim`,
  `minta_klaim_cepat`, `ajukan_transfer`, `laporan_komisi`, `klaim_ehc_saya`, view `kas_sales` & `ehc_cepat_siap`, plus
  trigger baru `sol_jaga_saldo_ehc` (sales_order_lines), `so_jaga_saldo_ehc` & `so_jaga_hapus_ehc` (sales_orders).
  Migrasi 120–139 yang menyentuh objek itu WAJIB dibangun dari `pg_get_functiondef` di DEV, bukan dari berkas lama.

**Dikonfirmasi Hannes (7 Okt)** untuk #50/#51: HP wajib untuk semua peran (termasuk owner/GM); persen GM juga untuk barang
yang belum punya price list; SP lama yang belum diklaim ikut dihitung ulang (DEV: 7 SP, +Rp 1.750.185); GM wajib mengisi
persen saat menyetujui harga (boleh 0, maks 50%).

| # | Ringkas | Status |
|---|---|---|
| 50 | Cek Vonny: `cek_kelayakan_vonny` (berkas 120, baca saja) memeriksa tiap SP di Double Check dengan syarat yang sama dengan putuskan_vonny_cek + lengkapi_pelanggan_sp + buat_pelanggan_baru. Daftar: kartu "Belum bisa diloloskan" + alasan merah per SP + "perlu: Vonny / owner-GM / GM / sales". Laci: kotak status, cek langsung saat mengetik No. HP/alamat, tombol loloskan terkunci sampai beres (Tahan tetap bisa). Keputusan Hannes: SP tetap tidak lolos sebelum beres — Vonny diberi tahu alasannya. **Berkas 121** (hasil review): cek juga mencerminkan pelanggan daftar hitam (PO belum bertuan), PO yang sudah atas nama pelanggan lain, dan SP tanpa sales yang cocok dengan pelanggan Office; indeks `kunci_nama_pelanggan(nama/nama_lama)` + ANALYZE (cek 9 SP: ±740 → ±8 ms). Laci memeriksa ulang saat dibuka + tombol "Periksa ulang"; hasil cek hanya menulis ke laci SP-nya sendiri; galat jaringan/batas waktu ≠ DB lama (flag kuning, tombol tidak dikunci — DB tetap menolak) | **selesai (DB 120+121 + FE)**; uji DEV paritas 9/9 + 9/9 (Vonny & owner, termasuk 3 kasus baru); layar 32/32 + 16/16; pertanyaan no. 2 (HP wajib di form SP) belum dijawab |
| 50b | HP wajib (keputusan Hannes 7 Okt): trigger `so_yy_hp_wajib` (**berkas 122**) — SP tanpa customer_id wajib No. HP sah sejak dibuat (semua peran); SP lama tanpa HP tidak dikunci (diperiksa hanya bila No. HP diubah / pelanggan dilepas; ganti Kepada bebas). FE: label & keterangan No. HP langsung, validasi sebelum nomor SP diambil, nama perusahaan diubah sesudah memilih → pelanggan dilepas (dulu customer_id lama menempel), Minta ubah SP memvalidasi No. HP; jalur "ubah langsung" owner/GM menutup usulan yang ditolak DB (dulu tertinggal 'menunggu' dan mengunci usulan berikutnya) · Berkas 124: SP batal yang dihidupkan lagi diperiksa seperti SP baru; mode tanpa PO / PO menyusul tanpa kotak Kepada kedua (dulu bisa mengganti pembeli tanpa melepas pelanggan); jalur ubah langsung tidak menutup usulan bila koneksi putus | **selesai (DB 122+124 + FE)**; uji DEV rollback 20 skenario (sales/owner/Vonny, Minta ubah, PO lama 35, no-op 54 SP); layar 35/35 |
| 51 | Komisi (keputusan Hannes 7 Okt: tampilkan; persen GM dipakai). **Berkas 123**: `komisi_pct_baris` (satu tempat urutan persen, = CASE lama), `so_baris_hitung` + kolom `pct_berlaku`/`sumber_pct` (pct lama identik 91/91), `so_ringkas.komisi` = Σ nilai DPP × pct_berlaku (kolom lain identik → gerbang GM/status tidak bergeser), CHECK `so_gm_pct_wajar` 0–50%, RPC `pratinjau_komisi_sp` & `komisi_sp_saya`. DEV: 7 SP bergeser +Rp 1.750.185 (007/009/010/011/015/020/032 -IX), 0 sudah diklaim; klaim #12/#13 tetap; ehc_saldo_sp/ehc_belum_klaim md5 identik. FE: form SP perkiraan per baris & total; laci GM wajib persen (0–50) + pratinjau Rupiah, Tolak tidak menulis persen; kolom "Komisi Anda" & detail SP untuk sales. Sesi EHC/komisi setuju (#54 menyisipkan persen per baris di CASE pct_berlaku) · **Berkas 124** (hasil review): persen keputusan harga pindah ke kolom baru `gm_pct_harga` (diisi dari gm_pct SP yang sudah disetujui → angka tidak bergeser; dijaga GM/owner, 0–50%); `gm_pct` kembali KHUSUS persen telat — dulu persen harga yang kini wajib membuat SP tak pernah masuk antrean telat & persen harga dipakai untuk seluruh SP; OFFSET 0 di so_baris_hitung (so_ringkas ±2× lebih cepat); komisi_sp_saya "menunggu" hanya bila harga belum diputus | **selesai (DB 123+124 + FE)**; uji DEV paritas pratinjau = SP tersimpan, 12 uji peran; layar 33/33 |
| 52 | Muat ulang diam-diam saat pindah tab, klik tab yang sama, jendela kembali dilihat (visibilitychange/focus/pageshow), dan tombol **Muat ulang** di header. Data lama tetap tampil; gambar ulang ditunda saat mengetik / laci terbuka / form PO-SP-penawaran terisi · **7 Okt (keputusan Hannes):** tanpa refresh otomatis berkala, tetapi SETIAP pindah tab / kembali ke jendela data ditarik ulang — jeda per tab (20–120 dtk) dihapus, tinggal 3 dtk penggabung pemicu beruntun; tab Kas Sales ikut terdaftar. Catatan: keluhan "harus refresh terus" terjadi di PROD yang belum memakai #52 | **selesai (FE)**, lihat catatan #52 |
| 53 | Keputusan Hannes 7 Okt: kelompok baru RHAJA untuk RHJ R & RHJ PP. DEV sudah sejak 1 Sep (Ubah massal oleh Hannes, tidak ada berkas db/) → **berkas 125** membawa daftar DEV yang sama ke PROD (59 produk: RHJ R*, RHJ PP*, RHJ BLACK PP 2", 2" H/R grey rubber, ROLLER PHINOLIQ 1"), dicocokkan per pasangan (kode, kelompok lama) → idempoten; kolom bahan diisi bila kosong (Karet 28, Nylon 2; PP dibiarkan kosong — products_bahan_sah tidak punya "PP"). Merek/kategori/tipe set/price list/komisi tidak berubah | **selesai (DB 125)**; uji DEV rollback: simulasi PROD 59 dipindah, 0 produk lain, ulang = 0 |
| 54 | → sesi EHC/komisi (menunggu konfirmasi) | — |
| 55 | Belum ada unduh/cetak penawaran untuk peran apa pun | tanya: isi kop/penutup, logo |
| 56 | Dokumen penawaran (pratinjau & detail) kini punya kolom **Spesifikasi** tersendiri (baris baru dipertahankan); isian spesifikasi jadi textarea multi-baris (dulu input 1 baris membuang Enter dari spesifikasi master) | **selesai (FE)** |
| 57 | Set dipecah per pcs di SP sesuai ATURAN; usul tampilan berkelompok + kolom penanda set | tanya: "set (sudah diubah)" & kunci qty |
| 58 | Indo Kida (Iwan, 2604) vs Garuda Metalindo (Hendri, 2354) — menabrak #48 | tanya: opsi A ganti nama / B induk / C gabung |
| 59 | Form penawaran menawarkan "+ Pakai … sebagai item baru"; item diusulkan (`usulkan_produk`) saat penawaran disimpan, lalu disahkan owner/GM/staff; dokumen tanpa "(usulan)" | **inti selesai (FE)**; tanya: tombol "Buang" usulan yang tak jadi order |
| 60 | UP, e-mail, diskon, TOP belum ada | tanya: bentuk diskon/TOP/UP |
| 61 | → sesi EHC/komisi (menunggu konfirmasi) | — |

### Catatan #52 untuk sesi lain (mekanisme muat ulang)
- Daftarkan tab di `MUAT_DIAM[tab] = { muat, gambar, boleh?, kunci?, kunciJalan?, jeda?, tunda? }` (index.html, blok
  "#52 · MUAT ULANG DIAM-DIAM" sesudah `pindahTab`). `muatUlangDiam(opsi)` dipanggil otomatis; `tandaiBasi(tab)` memaksa
  tarikan berikutnya; `gambarDiam(tab)` menggambar ulang dengan penundaan aman. Jeda bawaan 20 dtk (`SEGAR.jedaBawaan`).
- Sudah terdaftar: crm, pelanggan, khusus, penawaran, po, sp, performa, vonnycek, kirim, lunas, ehc, komisi, gm, dan grup
  muatSemua (ringkas/order/bayar/tindak/harga/produk/sinkron/pengguna/riwayat → `muatSemuaDiam`). **Belum**: kas, laporan,
  report (tombol Muat ulang disembunyikan di sana). Sesi EHC/komisi: saat merombak layar EHC/Komisi/Kas/Laporan, daftarkan
  ulang entrinya; loader dengan pengaman `memuat` sebaiknya memakai pola `var awal = X.dimuat; … if (awal && !X.dimuat) { X.memuat = false; return muatX(); }`.
- `muatSemua(diam)`: `true` = tanpa layar "Memuat data…" (dipakai `segarkanUsulan`). Produk & price list juga disegarkan
  di latar tiap ≥ 5 menit saat pindah tab.
- Kait uji `window.__segar` hanya di localhost/file:.
- Review adversarial #52 (workflow 4 reviewer + verifikator per temuan): 26 temuan terkonfirmasi (±13 unik) — semua
  diperbaiki: nomor gen PO/SP/usul kini mengembalikan janji tarikan terbaru (dulu bisa ping-pong tanpa akhir & panel
  macet "Memuat PO…"), PO/SP tidak lagi berbagi kunci, form PO kosong tidak menahan gambar ulang (qty bawaan 1),
  gambar ulang ditunda selama mouse/jari menekan & dilanjutkan 250 ms sesudah blur, gambar ulang yang dipicu tindakan
  pengguna (simpan/cari) tetap jalan sambil mengembalikan fokus kotak cari, rantai muat dibersihkan walau menggambar
  galat, tombol Muat ulang mencoba lagi bila tarikan terakhir gagal, muatSp menulis sekaligus sesudah ringkasan,
  muatLunas/muatPerforma diperiksa lagi sesudah ringkasan, segarkanUsulan kembali ke muatSemua biasa, pengaman yang
  sama di muatGm/muatEhc/muatKomisi (2 baris) & muatUsulan tidak mengosongkan daftar saat gagal, tombol di HP pindah
  ke pojok kanan atas. Uji layar: 14/14 (temuan) + 31/31 (#52) + 31/31 (#56 #59) + 36/36 (119).

## Jawaban Hannes 7 Okt (daftar konfirmasi)
- #52: tanpa refresh berkala; SETIAP pindah tab selalu segar → selesai (jeda 3 dtk).
- #53: kelompok RHAJA → selesai (berkas 125).
- #55: Hannes mengirim contoh penawaran yang biasa dikirim → menunggu.
- #57: setuju (a) set diubah → "set (sudah diubah)", (b) qty roda dalam set dikunci di SP dari PO, (c) SP lama per set bila cocok.
- #58: masalahnya penawaran dikirim ke SATU pelanggan, padahal grup pelanggan punya banyak perusahaan yang dipegang sales
  berbeda → Hannes bertanya cara menanganinya (usulan dikirim 7 Okt, menunggu jawaban).
- #59: opsi B — barang usulan dari penawaran baru masuk antrean GM setelah dipakai di PO.
- #60: diskon per baris (Rp/%) tanpa diskon total; TOP Cash/7/14/30/45/60/Lainnya (Riksa & Michael terkunci Cash); UP &
  e-mail otomatis dari data pelanggan, e-mail yang belum ada di data pelanggan otomatis disimpan ke sana.
- #54 & #61 dikerjakan sesi EHC/komisi.
- #50 lanjutan: alamat juga wajib di SP tanpa pelanggan master; No. HP yang sudah dipakai pelanggan lain DITOLAK saat SP
  disimpan (pesan tanpa nama pelanggan/sales lain, minta pilih dari daftar).
- #51 lanjutan: harga khusus hanya berlaku bila harganya DI BAWAH price list (di atas list kembali ke tier); Riksa & Michael
  tetap masuk antrean GM untuk harga di bawah list (komisi tetap flat 1%); penggolongan baris DIBEKUKAN (price list / harga
  khusus yang disahkan sesudah SP dibuat tidak mengubah komisi/gerbang SP itu).
- 16–19 (harga_ok direset saat baris berubah, Tolak telat, kosongkan gm_pct lama di PROD, klaim pelanggan belum bertuan):
  Hannes minta dijelaskan ulang (7 Okt) → menunggu jawaban.

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
8. **SP ditautkan sales ke pelanggannya sendiri lewat REST** (RLS so_tambah/so_ubah with_check pelanggan_saya): INSERT/PATCH
   customer_id ke pelanggan milik sendiri tanpa HP diterima — melompati aturan HP (berkas 122) dan penautan Vonny (#37).
9. **Tanggal SP tidak dijaga**: sales bisa INSERT/PATCH `sales_orders.tanggal` mundur (juga SP lunas). Snapshot price list
   (`isi_harga_list`) memakai tanggal itu → tier naik & gerbang GM terlewati (uji: SP tgl 12 Agu 'menunggu vonny' vs hari
   ini 'menunggu gm'). Usul: tanggal := current_date untuk selain owner/GM + kolom dijaga jaga_kolom_sales.

Bug/data non-keamanan yang dicatat:
- **gm_pct harga vs telat** — DIPISAH di berkas 124 (`gm_pct_harga`). Sisa: (a) SP yang disetujui SEBELUM 124 masih punya
  gm_pct (dari keputusan harga) → bila kelak telat, tidak masuk antrean telat & persen itu dipakai untuk seluruh SP (perilaku
  lama). Usul untuk PROD: kosongkan gm_pct SP yang tidak telat & belum diklaim sesudah 124 (dijalankan owner/GM; perlu
  keputusan Hannes). (b) Laci keputusan telat masih menulis harga_ok (Tolak telat = "harga ditolak") — area sesi EHC/komisi.
  (c) Untuk SP telat komisi_hitung = total × gm_pct sedangkan so_ringkas per baris — laporan_komisi diperbaiki sesi EHC.
- ajukan_ubah tidak memeriksa No. HP SP (hanya trigger saat diterapkan + validasi layar): usulan tak sah dari tab lama/REST
  ditolak saat GM menyetujui dan GM perlu menolaknya manual.
- `harga_ok` tidak direset saat baris SP berubah lewat Minta ubah SP → baris baru di bawah list ikut persen GM lama tanpa
  ditinjau (diambil sesi EHC di tahap #54, putuskan_ubah).
- Penggolongan baris tidak dibekukan: price list / harga khusus yang disahkan SESUDAH SP dibuat mengubah komisi SP lama
  (juga yang lunas, belum diklaim) dan bisa mengeluarkan baris dari gerbang GM tanpa keputusan (DEV: 018/IX, 008/X,
  011/X). Perlu keputusan Hannes: boleh berubah, atau dibekukan saat GM memutus / saat lunas.
- Harga khusus mengalahkan tier walau harga jual di atas list (mis. 0,5% padahal tier 5%) — perlu keputusan Hannes.
- Riksa/Michael (flat): baris di bawah list tidak masuk antrean GM (hanya Office yang dikecualikan di ATURAN B) — perlu
  keputusan Hannes.
- View `cash_belum_cocok.komisi_kalau_cash` memakai 5% untuk sales flat & belum memakai persen GM (tidak dipakai FE).
- `putuskan_ubah` (Minta ubah SP) menghapus & membuat ulang semua baris → gagal pada SP yang sudah punya surat jalan
  bertahap / qty batal (SP 159). (Area #54.)
- Jalur cek Vonny di laci Pengiriman (`formKirim`, ±index.html:10979) memanggil `lengkapi_pelanggan_sp` tanpa kotak
  HP/alamat — praktis tak terjangkau.
- Data DEV: pelanggan 5413 "BP. Nanang" (Alfred) ber-HP 622134567 = nomor isian Vonny; PT Shidachi Indo Jaya
  (Hendri) dijual Menik di SP 017/MCE/X.

## Langkah berikut
1. Hannes mencoba di DEV. Setelah Hannes mengetik "revisi selesai" → jalankan verifikator.
2. PR ke `main` hanya bila Hannes meminta. Migrasi 109–114 belum pernah dijalankan di PROD.
