# PETA-KODE — index.html

Dibuat otomatis oleh `alat/peta-kode.py` pada 2026-10-10 dari `index.html` (19,389 baris). Jangan disunting tangan — jalankan ulang skripnya. Nomor baris berlaku untuk versi itu; kalau meleset sedikit, cari nama fungsinya dengan `grep -n`.

**Cara pakai (hemat token):** cari bagian atau fungsi di peta ini dulu, lalu baca `index.html` hanya pada rentang barisnya (`Read` dengan offset/limit). Definisi database: migrasi di `db/NNN-*.sql`; objek yang hanya ada di DEV (migrasi 1–58) ada di `db/_snapshot/`.

## Tab → fungsi panel → peran

| Tab (id) | Label | Fungsi panel | Baris | Peran yang melihat tab |
|---|---|---|---|---|
| `crm` | CRM · Pipeline | `panelCrm` | 1434 | owner, gm, staff, finance, sales |
| `pelanggan` | Pelanggan | `panelPelangganTab` | 8226 | owner, gm, staff, finance, sales |
| `harga` | Price List | `panelHarga` | 16613 | owner, gm, staff, finance, sales |
| `khusus` | Harga Special | `panelKhusus` | 13924 | owner, gm, staff, finance, sales |
| `penawaran` | Penawaran | `panelPenawaran` | 9083 | owner, gm, staff, sales, vonny |
| `po` | Upload PO | `panelPo` | 4758 | owner, gm, staff, finance, sales, liesian, ichi, vonny, lenni |
| `sp` | Surat Pesanan | `panelSp` | 6405 | owner, gm, staff, finance, sales, liesian, ichi, vonny, lenni |
| `performa` | Performa Sales | `panelPerforma` | 9874 | owner, gm |
| `vonnycek` | Double Check Vonny | `panelVonnyCek` | 10468 | owner, gm, vonny |
| `kirim` | Pengiriman & Invoice | `panelKirim` | 10702 | owner, gm, staff, finance, liesian, ichi, vonny, lenni, sales |
| `lunas` | Pelunasan | `panelLunas` | 11187 | owner, gm, staff, finance, liesian, ichi, vonny, lenni, sales |
| `ehc` | EHC | `panelEhc` | 11727 | owner, gm, finance, sales |
| `komisi` | Komisi | `panelKomisi` | 12323 | owner, gm, finance, sales |
| `kas` | Kas Sales | `panelKas` | 12699 | owner, gm, finance, sales |
| `laporan` | Laporan Finance | `panelLaporan` | 12849 | owner, gm, finance, lenni |
| `gm` | Menunggu Konfirmasi GM | `panelGmAntre` | 13383 | owner, gm, staff, sales |
| `report` | Unduh Laporan | `panelReport` | 14327 | owner, gm, staff, finance, sales, liesian, ichi, vonny, lenni |
| `ringkas` | Ringkasan | `panelRingkas` | 14888 | owner, gm, staff, finance |
| `order` | Order | `panelOrder` | 15222 | owner, gm, staff, finance, sales, selfie, vonny |
| `bayar` | Pembayaran | `panelBayar` | 15322 | owner, gm, staff, finance |
| `produk` | Produk | `panelProduk` | 17536 | owner, gm, staff, vonny |
| `tindak` | Perlu Ditindak | `panelTindak` | 15380 | owner, gm, staff, finance |
| `sinkron` | Sinkron Sheet | `panelSinkron` | 15809 | owner, gm |
| `pengguna` | Pengguna | `panelPengguna` | 15647 | owner |
| `riwayat` | Riwayat | `panelRiwayat` | 16019 | owner, gm |

Keamanan ditegakkan di DB; daftar peran di atas hanya menyembunyikan tab.

## Bagian

| Baris | Bagian |
|---|---|
| 890–901 | CONFIG — isi dua baris ini sesudah project Supabase dibuat. |
| 902–936 | SITUS — satu berkas, dua alamat. |
| 937–1326 | Di bawah ini tidak perlu diubah. |
| 1327–1964 | CRM — pipeline penjualan dan master pelanggan. |
| 1965–2263 | XLSX kecil — tulis dan baca, tanpa pustaka luar. |
| 2264–2701 | UBAH MASSAL LEWAT EXCEL — unduh template, isi di Excel, unggah lagi. |
| 2702–3098 | SESI — bertahan antar kunjungan, tapi tidak selamanya |
| 3099–3632 | TURUNAN PRODUK — bracket, bahan roda, ukuran roda |
| 3633–7815 | ALUR PENJUALAN — Upload PO → Surat Pesanan |
| 7816–7975 | LAYAR LANJUTAN — Pelanggan + 8 alur yang tabelnya sudah ada di database |
| 7976–8574 | 1 · PELANGGAN — tab sendiri |
| 8575–9801 | 2 · PENAWARAN |
| 9802–10233 | 3 · PERFORMA SALES |
| 10234–10391 | MESIN HALAMAN — satu daftar dipecah jadi beberapa halaman bertombol |
| 10392–11141 | 4 · PENGIRIMAN & INVOICE |
| 11142–11503 | 5 · PELUNASAN |
| 11504–12232 | 6 · EHC — budget marketing per customer & sales |
| 12233–12690 | 6b · KOMISI — sales mengklaim komisinya sendiri |
| 12691–12746 | 7 · KAS SALES — view, bukan tabel |
| 12747–13344 | 8 · LAPORAN FINANCE |
| 13345–13879 | 9 · MENUNGGU KONFIRMASI GM |
| 13880–14086 | 10 · HARGA SPECIAL — kesepakatan yang diingat |
| 14087–15768 | 11 · UNDUH LAPORAN |
| 15769–16575 | SINKRON PRICE LIST DARI GOOGLE SHEETS |
| 16576–16860 | PRICE LIST |
| 16861–17336 | EDIT MASSAL — harga jual, HPP, dan empat kolom keterangan produk |
| 17337–17860 | PRODUK — master, sumber barang, kode pabrik |
| 17861–18119 | PRICE LIST UNTUK CUSTOMER |
| 18120–18184 | DOKUMEN ORDER — berkas disimpan di Supabase Storage (bucket tertutup), |
| 18185–18522 | DOKUMEN ORDER — kolom bernama per dokumen, bukan satu dropdown |
| 18523–19389 | BARIS INVOICE — ditempel dari Excel, dicocokkan, diuji, baru disimpan |

## Rincian per bagian

### 937–1326 · Di bawah ini tidak perlu diubah.

- **Sub-bagian:** alat angka & tanggal (1031); waktu Jakarta (1164); simpanan sesi (best effort; kalau diblokir, cukup di memori) (1263); lapisan REST Supabase (tanpa SDK, murni fetch) (1272)
- **Fungsi utama:** `simpan` 1268
- Fungsi lain: 57 (cari dengan `grep -n "^function" index.html`)

### 1327–1964 · CRM — pipeline penjualan dan master pelanggan.

- **Sub-bagian:** muat (1392); saring (1420); panel (1433); laci lead (1576); lead baru: nomor HP diketik duluan (1703); pelanggan (1784)
- **Fungsi utama:** `muatCrm` 1393, `panelCrm` 1434, `gambarKejadian` 1692, `panelPelanggan` 1785, `gambarRapiNama` 1814, `gambarHasilPelanggan` 1909
- Fungsi lain: 22 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `batalkan_lead` 1665, `pratinjau_nama_pelanggan` 1810, `terapkan_rapi_nama` 1842, `pulihkan_nama_pelanggan` 1852, `rhj_nama_rapi` 1884
- **Tabel/view:** `customers` (GET/PATCH/POST), `lead_events` (GET/POST), `lead_nilai` (POST), `leads` (GET/PATCH/POST), `sales_reps` (GET)

### 1965–2263 · XLSX kecil — tulis dan baca, tanpa pustaka luar.

- **Sub-bagian:** CRC32 (1979); ZIP tulis (metode "stored", tanpa pemampatan) (2003); ZIP baca (2043); XML kecil (2083); tulis satu berkas xlsx (2095); baca lembar pertama jadi larik baris (2208)
- Fungsi lain: 11 (cari dengan `grep -n "^function" index.html`)

### 2264–2701 · UBAH MASSAL LEWAT EXCEL — unduh template, isi di Excel, unggah lagi.

- **Sub-bagian:** masuk / keluar (2664)
- Fungsi lain: 9 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `hitung_edit_massal` 2516, `hitung_kolom_massal` 2518, `terapkan_edit_massal` 2644, `terapkan_kolom_massal` 2644

### 2702–3098 · SESI — bertahan antar kunjungan, tapi tidak selamanya

- **Sub-bagian:** menganggur (2785); peringatan hitung mundur (2832); pemeriksa berkala (2859); antar tab (2877); muat data & hitung turunan (3012)
- **Fungsi utama:** `simpanSesi` 2752, `muatSesi` 2766, `gambarHitung` 2834, `bukaPeringatan` 2846, `muatUlang` 2951, `muatSemua` 3028
- Fungsi lain: 18 (cari dengan `grep -n "^function" index.html`)

### 3099–3632 · TURUNAN PRODUK — bracket, bahan roda, ukuran roda

- **Sub-bagian:** daftar pilihan diambil dari katalog yang ADA, bukan daftar tetap (3162); tab (3414)
- Fungsi lain: 28 (cari dengan `grep -n "^function" index.html`)

### 3633–7815 · ALUR PENJUALAN — Upload PO → Surat Pesanan

- **Sub-bagian:** nama sales: MEMILIH ≠ MENYARING (3806); keterangan "sales dari master pelanggan" (3822); memuat (3986); pencarian pelanggan: 5.395 baris, jadi disaring di server (4140); kotak cari produk: master produk sudah ada di memori (4226); (b) urut generik DOM (4600); mode "PO menyusul": perusahaan, alasan, dan baris yang diketik (7056); harga khusus yang SUDAH ada untuk pelanggan ini (7207); laci: request harga & komisi khusus (7456); potongan bersama (7521)
- **Fungsi utama:** `muatRepCash` 3972, `muatPo` 3990, `muatSp` 4066, `panelPo` 4758, `gambarTautkanPo` 5269, `muatUsul` 5441, `bukaDetailSpId` 5459, `muatInfoBarisSp` 5602, `kirimBatalBaris` 5696, `simpanPo` 6296, `panelSp` 6405, `muatKhususPelanggan` 7223, `simpanSp` 7303, `panelBelum` 7800
- Fungsi lain: 132 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `sales_rep_cash_only` 3974, `cek_pemilik_pelanggan` 4202, `lampirkan_po` 4972, `batalkan_po` 5194, `batalkan_sp` 5194, `tautkan_po_sp` 5398, `tandai_sp_tanpa_po` 5408, `izinkan_invoice_tanpa_po` 5422, `lengkapi_pelanggan_sp` 5564, `batalkan_baris_sp` 5703, `pulihkan_baris_sp` 5703, `ajukan_ubah` 5892, `putuskan_ubah` 5901, `po_dobel` 6067, `usulkan_produk` 6318, `buat_pelanggan_baru` 6329, `nomor_sp_baru` 7362, `ajukan_harga_khusus` 7402
- **Tabel/view:** `customers` (GET), `harga_khusus` (GET), `po_batal_ringkas` (GET), `po_belum_sp` (GET), `po_lines` (POST), `po_nomor_dobel` (GET), `po_ringkas` (GET), `purchase_orders` (POST), `sales_order_lines` (POST), `sales_orders` (GET/POST), `sales_reps` (GET), `so_kirim` (GET), `so_kirim_sisa` (GET), `so_ringkas` (GET), `sp_menunggu_po` (GET), `sp_nilai_batal` (GET), `usul_ubah` (GET)
- Storage: 2 panggilan

### 7816–7975 · LAYAR LANJUTAN — Pelanggan + 8 alur yang tabelnya sudah ada di database

- **Sub-bagian:** permintaan yang ikut menghitung total baris (7905)
- Fungsi lain: 7 (cari dengan `grep -n "^function" index.html`)

### 7976–8574 · 1 · PELANGGAN — tab sendiri

- **Sub-bagian:** pagination (8073)
- **Fungsi utama:** `muatPelanggan` 8043, `panelPelangganLain` 8178, `panelPelangganTab` 8226, `simpanPelangganTab` 8518
- Fungsi lain: 8 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `pelanggan_sales_lain` 8208, `pindah_semua_pelanggan` 8420
- **Tabel/view:** `customers` (PATCH/POST), `leads` (GET), `pelanggan_per_sales` (GET)

### 8575–9801 · 2 · PENAWARAN

- **Sub-bagian:** form penawaran (9137); daftar penawaran tersimpan + pencarian (#44) (9611); ringkasan SP: permintaan terpisah, bukan embed (9775)
- **Fungsi utama:** `muatPenawaran` 8626, `muatSet` 8664, `gambarKelolaSet` 8748, `gambarSetEdit` 8807, `simpanSet` 8871, `muatTipeRoda` 8955, `panelPenawaran` 9083, `gambarPratinjauPenawaran` 9549, `simpanPenawaran` 9566
- Fungsi lain: 49 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `simpan_set` 8885, `hapus_set` 8899, `pilihan_tipe_roda` 8958, `rhj_nama_rapi` 9545, `simpan_penawaran` 9574
- **Tabel/view:** `product_sets` (GET), `quotes` (GET), `so_ringkas` (GET)

### 9802–10233 · 3 · PERFORMA SALES

- **Sub-bagian:** PENULIS XLSX TANPA PUSTAKA LUAR (9972); PERIODE (10106)
- **Fungsi utama:** `muatPerforma` 9846, `panelPerforma` 9874
- Fungsi lain: 18 (cari dengan `grep -n "^function" index.html`)
- **Tabel/view:** `leads` (GET), `sales_orders` (GET)

### 10234–10391 · MESIN HALAMAN — satu daftar dipecah jadi beberapa halaman bertombol

- **Fungsi utama:** `muatHalaman` 10361
- Fungsi lain: 8 (cari dengan `grep -n "^function" index.html`)

### 10392–11141 · 4 · PENGIRIMAN & INVOICE

- **Fungsi utama:** `kirimHal` 10437, `muatVonnyCek` 10451, `panelVonnyCek` 10468, `simpanIndustri` 10548, `muatKirim` 10690, `panelKirim` 10702, `gambarKirimPartial` 11003
- Fungsi lain: 12 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `set_industri_pelanggan` 10549, `lengkapi_pelanggan_sp` 10661, `putuskan_vonny_cek` 10665, `batal_surat_jalan` 11105, `tambah_surat_jalan` 11128
- **Tabel/view:** `sales_order_lines` (GET), `sales_orders` (GET/PATCH), `so_kirim` (GET)

### 11142–11503 · 5 · PELUNASAN

- **Fungsi utama:** `muatLunas` 11161, `panelLunas` 11187
- Fungsi lain: 5 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `cocokkan_cash_sp` 11478
- **Tabel/view:** `sales_orders` (PATCH)

### 11504–12232 · 6 · EHC — budget marketing per customer & sales

- **Sub-bagian:** empat halaman EHC (titik 19) (11517); berkas 50 · pencairan cepat (11646); berkas 50 · meminta pencairan cepat untuk klaim yang SUDAH ada (11901); laci klaim baru (11980)
- **Fungsi utama:** `muatEhc` 11576, `muatEhcHal` 11613, `panelEhc` 11727, `muatPicUntukSp` 12067, `gambarRekPic` 12092, `simpanKlaimEhc` 12152
- Fungsi lain: 18 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `minta_klaim_cepat` 11929, `batalkan_klaim_cepat` 11945, `simpan_pic_rekening` 12196, `ajukan_klaim_ehc_cepat` 12213, `ajukan_klaim_ehc` 12213
- **Tabel/view:** `customer_pics` (GET), `ehc_belum_klaim` (GET)
- Storage: 1 panggilan

### 12233–12690 · 6b · KOMISI — sales mengklaim komisinya sendiri

- **Sub-bagian:** empat halaman komisi (titik 20) (12260); laci: isi rekening sales (finance) (12525); laci: klaim komisi (12557)
- **Fungsi utama:** `muatKomisi` 12294, `muatKomisiHal` 12315, `panelKomisi` 12323, `gambarHitungKomisi` 12597, `gambarBerkasKomisi` 12623, `simpanKlaimKomisi` 12644
- Fungsi lain: 6 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `simpan_rekening_sales` 12544, `ajukan_klaim_komisi` 12671
- **Tabel/view:** `komisi_belum_klaim` (GET), `sales_rep_rekening` (GET)
- Storage: 2 panggilan

### 12691–12746 · 7 · KAS SALES — view, bukan tabel

- **Fungsi utama:** `panelKas` 12699
- **Tabel/view:** `kas_sales` (GET)

### 12747–13344 · 8 · LAPORAN FINANCE

- **Sub-bagian:** batch transfer (12851); persetujuan GM sebelum transfer (berkas 48) (12861); berkas 50 · "EHC emergency" (12957)
- **Fungsi utama:** `panelLaporan` 12849, `muatBatch` 12855, `muatPengajuan` 12868, `ajukanTransfer` 12892, `gambarLaporan` 13082
- Fungsi lain: 15 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `ajukan_transfer` 12898, `tarik_pengajuan_transfer` 12914, `rekap_transfer` 12937, `isi_referensi_batch` 12951, `rekap_ehc_cepat` 12998
- **Tabel/view:** `ehc_cepat_siap` (GET), `ehc_klaim` (GET), `komisi_klaim` (GET), `transfer_batch` (GET), `transfer_pengajuan` (GET)

### 13345–13879 · 9 · MENUNGGU KONFIRMASI GM

- **Sub-bagian:** keputusan atas usulan ubah PO / SP (13480)
- **Fungsi utama:** `muatGm` 13367, `panelGmAntre` 13383, `muatKonteksHpp` 13643, `gambarKonteksHpp` 13648
- Fungsi lain: 5 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `putuskan_ubah` 13612, `gm_konteks_keputusan` 13644, `putuskan_ubah_rekening` 13813, `putuskan_transfer` 13822, `putuskan_klaim_cepat` 13832, `putuskan_harga_khusus` 13839, `putuskan_kirim` 13852
- **Tabel/view:** `antrean_gm` (GET), `sales_orders` (PATCH), `usul_ubah` (GET)

### 13880–14086 · 10 · HARGA SPECIAL — kesepakatan yang diingat

- **Sub-bagian:** penyalur: tab mana menggambar apa (14086)
- **Fungsi utama:** `muatKhusus` 13899, `panelKhusus` 13924
- Fungsi lain: 2 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `ubah_harga_khusus` 14071

### 14087–15768 · 11 · UNDUH LAPORAN

- **Sub-bagian:** gambar semua panel (14689); saringan tab Order (14988); isi kiriman impor untuk sales (titik 9) (15139)
- **Fungsi utama:** `panelReport` 14327, `gambar` 14690, `panelRingkas` 14888, `panelOrderSales` 15050, `muatItemImpor` 15148, `gambarItemImpor` 15164, `panelOrder` 15222, `panelBayar` 15322, `panelTindak` 15380, `muatAkunSales` 15600, `panelPengguna` 15647
- Fungsi lain: 29 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `laporan_piutang` 14121, `laporan_faktur` 14142, `laporan_komisi` 14167, `laporan_penjualan` 14196, `laporan_margin_produk` 14232, `laporan_margin_sp` 14257, `laporan_hpp_kosong` 14281, `setel_akun_sales` 15744
- **Tabel/view:** `akun_sales` (GET), `item_impor_ringkas_sales` (GET), `item_impor_untuk_sales` (GET), `profiles` (PATCH)

### 15769–16575 · SINKRON PRICE LIST DARI GOOGLE SHEETS

- **Sub-bagian:** laci isian (16052); form order (16223); form pembayaran (16434)
- **Fungsi utama:** `panelSinkron` 15809, `panelRiwayat` 16019, `bukaLaci` 16070, `gambarUlangAman` 16213, `gambarRingkasBayar` 16341, `simpanOrder` 16359, `simpanBayar` 16543
- Fungsi lain: 17 (cari dengan `grep -n "^function" index.html`)
- **Tabel/view:** `orders` (DELETE/PATCH/POST), `payments` (DELETE/PATCH/POST), `suppliers` (POST), `sync_log` (GET), `sync_sumber` (GET/PATCH/POST)

### 16576–16860 · PRICE LIST

- **Fungsi utama:** `panelHarga` 16613, `simpanHargaHpp` 16810
- Fungsi lain: 8 (cari dengan `grep -n "^function" index.html`)

### 16861–17336 · EDIT MASSAL — harga jual, HPP, dan empat kolom keterangan produk

- Fungsi lain: 7 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `hitung_edit_massal` 17123, `hitung_kolom_massal` 17128, `terapkan_edit_massal` 17244, `terapkan_kolom_massal` 17252, `batalkan_massal` 17312
- **Tabel/view:** `edit_massal` (GET)

### 17337–17860 · PRODUK — master, sumber barang, kode pabrik

- **Fungsi utama:** `muatUsulan` 17381, `panelProduk` 17536, `simpanProduk` 17749
- Fungsi lain: 11 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `sahkan_produk_usulan` 17499, `hapus_produk` 17743
- **Tabel/view:** `factory_codes` (PATCH), `price_list` (POST), `product_costs` (POST), `products` (PATCH/POST), `usulan_produk` (GET)

### 17861–18119 · PRICE LIST UNTUK CUSTOMER

- **Sub-bagian:** penjaga untuk LAPORAN INTERNAL (17995)
- Fungsi lain: 5 (cari dengan `grep -n "^function" index.html`)

### 18120–18184 · DOKUMEN ORDER — berkas disimpan di Supabase Storage (bucket tertutup),

- **Fungsi utama:** `bukaLampiranPo` 18154
- Fungsi lain: 5 (cari dengan `grep -n "^function" index.html`)
- Storage: 2 panggilan

### 18185–18522 · DOKUMEN ORDER — kolom bernama per dokumen, bukan satu dropdown

- **Fungsi utama:** `gambarDokumen` 18245, `simpanNomorTahap` 18399
- Fungsi lain: 8 (cari dengan `grep -n "^function" index.html`)
- **RPC:** `revisi_no_invoice` 18426, `tandai_diterima` 18478
- **Tabel/view:** `documents` (DELETE/POST), `orders` (PATCH)
- Storage: 4 panggilan

### 18523–19389 · BARIS INVOICE — ditempel dari Excel, dicocokkan, diuji, baru disimpan

- **Sub-bagian:** daftar baris di laci order (18590); penguraian tempelan (18649); seluruh perubahan harga, dihitung sekali untuk semua baris (18729); laci tempel (18766); jalan (19070)
- **Fungsi utama:** `gambarBaris` 18591
- Fungsi lain: 14 (cari dengan `grep -n "^function" index.html`)
- **Tabel/view:** `factory_codes` (GET/POST), `import_lines` (DELETE/POST), `profiles` (GET)

## Indeks RPC → baris pemanggil di index.html

| RPC | Baris |
|---|---|
| `ajukan_harga_khusus` | 7402 |
| `ajukan_klaim_ehc` | 12213 |
| `ajukan_klaim_ehc_cepat` | 12213 |
| `ajukan_klaim_komisi` | 12671 |
| `ajukan_transfer` | 12898 |
| `ajukan_ubah` | 5892 |
| `batal_surat_jalan` | 11105 |
| `batalkan_baris_sp` | 5703 |
| `batalkan_klaim_cepat` | 11945 |
| `batalkan_lead` | 1665 |
| `batalkan_massal` | 17312 |
| `batalkan_po` | 5194 |
| `batalkan_sp` | 5194 |
| `buat_pelanggan_baru` | 6329 |
| `cek_pemilik_pelanggan` | 4202 |
| `cocokkan_cash_sp` | 11478 |
| `gm_konteks_keputusan` | 13644 |
| `hapus_produk` | 17743 |
| `hapus_set` | 8899 |
| `hitung_edit_massal` | 2516, 17123 |
| `hitung_kolom_massal` | 2518, 17128 |
| `isi_referensi_batch` | 12951 |
| `izinkan_invoice_tanpa_po` | 5422 |
| `lampirkan_po` | 4972 |
| `laporan_faktur` | 14142 |
| `laporan_hpp_kosong` | 14281 |
| `laporan_komisi` | 14167 |
| `laporan_margin_produk` | 14232 |
| `laporan_margin_sp` | 14257 |
| `laporan_penjualan` | 14196 |
| `laporan_piutang` | 14121 |
| `lengkapi_pelanggan_sp` | 5564, 10661, 10938 |
| `minta_klaim_cepat` | 11929 |
| `nomor_sp_baru` | 7362 |
| `pelanggan_sales_lain` | 8208 |
| `pilihan_tipe_roda` | 8958 |
| `pindah_semua_pelanggan` | 8420 |
| `po_dobel` | 6067 |
| `pratinjau_nama_pelanggan` | 1810 |
| `pulihkan_baris_sp` | 5703 |
| `pulihkan_nama_pelanggan` | 1852 |
| `putuskan_harga_khusus` | 13839 |
| `putuskan_kirim` | 13852 |
| `putuskan_klaim_cepat` | 13832 |
| `putuskan_transfer` | 13822 |
| `putuskan_ubah` | 5901, 13612 |
| `putuskan_ubah_rekening` | 13813 |
| `putuskan_vonny_cek` | 10665, 10676, 10941, 10953 |
| `rekap_ehc_cepat` | 12998 |
| `rekap_transfer` | 12937 |
| `revisi_no_invoice` | 18426 |
| `rhj_nama_rapi` | 1884, 9545 |
| `sahkan_produk_usulan` | 17499 |
| `sales_rep_cash_only` | 3974 |
| `set_industri_pelanggan` | 10549 |
| `setel_akun_sales` | 15744 |
| `simpan_penawaran` | 9574 |
| `simpan_pic_rekening` | 12196 |
| `simpan_rekening_sales` | 12544 |
| `simpan_set` | 8885 |
| `tambah_surat_jalan` | 11128 |
| `tandai_diterima` | 18478 |
| `tandai_sp_tanpa_po` | 5408, 7395 |
| `tarik_pengajuan_transfer` | 12914 |
| `tautkan_po_sp` | 5398 |
| `terapkan_edit_massal` | 2644, 17244 |
| `terapkan_kolom_massal` | 2644, 17252 |
| `terapkan_rapi_nama` | 1842 |
| `ubah_harga_khusus` | 14071 |
| `usulkan_produk` | 6318, 7357 |

