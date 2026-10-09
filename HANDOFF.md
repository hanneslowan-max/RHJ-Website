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
  (PG 17) — jangan `drop trigger if exists` + `create trigger`. **8 Okt:** teks `delete` juga memicunya — termasuk
  `delete from` di DALAM badan fungsi (execute_sql & apply_migration: timeout / "cancelled", tidak ada yang berubah).
  Fungsi yang memuat `delete` (mis. `putuskan_ubah`) tidak bisa di-create-or-replace dari sesi ini; #57 memakai trigger.
- **Rilis #59/#60:** layar penawaran memuat kolom `up/email/top` + `quote_lines.diskon` dan mengirim `usulan_teks` per baris ke
  simpan_penawaran → unggah index.html bersama berkas **127 dan 129** (sebelum 129: daftar penawaran menampilkan galat
  "jalankan 129-…", dan baris barang baru di penawaran ditolak "belum memilih barang"). Data pelanggan memakai kolom
  `email` dengan cadangan otomatis bila kolomnya belum ada.
- **Rilis #57:** layar memuat kolom `set_*` di daftar SP / Double Check / Pengiriman → unggah index.html bersama
  berkas 126 (sebelum 126 dijalankan, daftar SP menampilkan galat "jalankan 126-set-di-sp.sql"; simpan SP tanpa set
  tetap jalan).
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
| 50 | Cek Vonny: `cek_kelayakan_vonny` (berkas 120, baca saja) memeriksa tiap SP di Double Check dengan syarat yang sama dengan putuskan_vonny_cek + lengkapi_pelanggan_sp + buat_pelanggan_baru. Daftar: kartu "Belum bisa diloloskan" + alasan merah per SP + "perlu: Vonny / owner-GM / GM / sales". Laci: kotak status, cek langsung saat mengetik No. HP/alamat, tombol loloskan terkunci sampai beres (Tahan tetap bisa). Keputusan Hannes: SP tetap tidak lolos sebelum beres — Vonny diberi tahu alasannya. **Berkas 121** (hasil review): cek juga mencerminkan pelanggan daftar hitam (PO belum bertuan), PO yang sudah atas nama pelanggan lain, dan SP tanpa sales yang cocok dengan pelanggan Office; indeks `kunci_nama_pelanggan(nama/nama_lama)` + ANALYZE (cek 9 SP: ±740 → ±8 ms). Laci memeriksa ulang saat dibuka + tombol "Periksa ulang"; hasil cek hanya menulis ke laci SP-nya sendiri; galat jaringan/batas waktu ≠ DB lama (flag kuning, tombol tidak dikunci — DB tetap menolak) | **selesai (DB 120+121 + FE)**; uji DEV paritas 9/9 + 9/9 (Vonny & owner, termasuk 3 kasus baru); layar 32/32 + 16/16; HP wajib dijawab Hannes 7 Okt (semua peran) → berkas 122 |
| 50b | HP wajib (keputusan Hannes 7 Okt): trigger `so_yy_hp_wajib` (**berkas 122**) — SP tanpa customer_id wajib No. HP sah sejak dibuat (semua peran); SP lama tanpa HP tidak dikunci (diperiksa hanya bila No. HP diubah / pelanggan dilepas; ganti Kepada bebas). FE: label & keterangan No. HP langsung, validasi sebelum nomor SP diambil, nama perusahaan diubah sesudah memilih → pelanggan dilepas (dulu customer_id lama menempel), Minta ubah SP memvalidasi No. HP; jalur "ubah langsung" owner/GM menutup usulan yang ditolak DB (dulu tertinggal 'menunggu' dan mengunci usulan berikutnya) · Berkas 124: SP batal yang dihidupkan lagi diperiksa seperti SP baru; mode tanpa PO / PO menyusul tanpa kotak Kepada kedua (dulu bisa mengganti pembeli tanpa melepas pelanggan); jalur ubah langsung tidak menutup usulan bila koneksi putus | **selesai (DB 122+124 + FE)**; uji DEV rollback 20 skenario (sales/owner/Vonny, Minta ubah, PO lama 35, no-op 54 SP); layar 35/35 |
| 51 | Komisi (keputusan Hannes 7 Okt: tampilkan; persen GM dipakai). **Berkas 123**: `komisi_pct_baris` (satu tempat urutan persen, = CASE lama), `so_baris_hitung` + kolom `pct_berlaku`/`sumber_pct` (pct lama identik 91/91), `so_ringkas.komisi` = Σ nilai DPP × pct_berlaku (kolom lain identik → gerbang GM/status tidak bergeser), CHECK `so_gm_pct_wajar` 0–50%, RPC `pratinjau_komisi_sp` & `komisi_sp_saya`. DEV: 7 SP bergeser +Rp 1.750.185 (007/009/010/011/015/020/032 -IX), 0 sudah diklaim; klaim #12/#13 tetap; ehc_saldo_sp/ehc_belum_klaim md5 identik. FE: form SP perkiraan per baris & total; laci GM wajib persen (0–50) + pratinjau Rupiah, Tolak tidak menulis persen; kolom "Komisi Anda" & detail SP untuk sales. Sesi EHC/komisi setuju (#54 menyisipkan persen per baris di CASE pct_berlaku) · **Berkas 124** (hasil review): persen keputusan harga pindah ke kolom baru `gm_pct_harga` (diisi dari gm_pct SP yang sudah disetujui → angka tidak bergeser; dijaga GM/owner, 0–50%); `gm_pct` kembali KHUSUS persen telat — dulu persen harga yang kini wajib membuat SP tak pernah masuk antrean telat & persen harga dipakai untuk seluruh SP; OFFSET 0 di so_baris_hitung (so_ringkas ±2× lebih cepat); komisi_sp_saya "menunggu" hanya bila harga belum diputus | **selesai (DB 123+124 + FE)**; uji DEV paritas pratinjau = SP tersimpan, 12 uji peran; layar 33/33 |
| 52 | Muat ulang diam-diam saat pindah tab, klik tab yang sama, jendela kembali dilihat (visibilitychange/focus/pageshow), dan tombol **Muat ulang** di header. Data lama tetap tampil; gambar ulang ditunda saat mengetik / laci terbuka / form PO-SP-penawaran terisi · **7 Okt (keputusan Hannes):** tanpa refresh otomatis berkala, tetapi SETIAP pindah tab / kembali ke jendela data ditarik ulang — jeda per tab (20–120 dtk) dihapus, tinggal 3 dtk penggabung pemicu beruntun; tab Kas Sales ikut terdaftar. Catatan: keluhan "harus refresh terus" terjadi di PROD yang belum memakai #52 | **selesai (FE)**, lihat catatan #52 |
| 53 | Keputusan Hannes 7 Okt: kelompok baru RHAJA untuk RHJ R & RHJ PP. DEV sudah sejak 1 Sep (Ubah massal oleh Hannes, tidak ada berkas db/) → **berkas 125** membawa daftar DEV yang sama ke PROD (59 produk: RHJ R*, RHJ PP*, RHJ BLACK PP 2", 2" H/R grey rubber, ROLLER PHINOLIQ 1"), dicocokkan per pasangan (kode, kelompok lama) → idempoten; kolom bahan diisi bila kosong (Karet 28, Nylon 2; PP dibiarkan kosong — products_bahan_sah tidak punya "PP"). Merek/kategori/tipe set/price list/komisi tidak berubah | **selesai (DB 125)**; uji DEV rollback: simulasi PROD 59 dipindah, 0 produk lain, ulang = 0 |
| 54 | → dikerjakan sesi EHC/komisi (dikonfirmasi Hannes 7 Okt; 9 Okt: tahap 1 menunggu Hannes menjalankan 140b di SQL Editor DEV) | sesi EHC |
| 55 | Belum ada unduh/cetak penawaran untuk peran apa pun | tanya: isi kop/penutup, logo |
| 56 | Dokumen penawaran (pratinjau & detail) kini punya kolom **Spesifikasi** tersendiri (baris baru dipertahankan); isian spesifikasi jadi textarea multi-baris (dulu input 1 baris membuang Enter dari spesifikasi master) | **selesai (FE)** |
| 57 | Tampilan SET di SP, data tetap per pcs (keputusan Hannes 7 Okt a/b/c). **Berkas 126**: kolom penanda `sales_order_lines.set_grup/set_nama/set_qty/set_isi` + CHECK `sol_set_lengkap`; trigger `sol_set_usul` (BEFORE INSERT, hanya saat `rhj.usul='on'`) membawa penanda ketika putuskan_ubah menyisipkan ulang baris SP — dari nilai_baru (layar baru mengirim kuncinya) atau nilai_lama (usulan dari layar lama); putuskan_ubah sendiri TIDAK diubah (alat MCP menolak SQL yang memuat teks "delete"; sesi EHC sudah diberi tahu). Data lama: SP dari PO ditandai hanya bila barisnya persis hasil pemecahan set (urutan produk komponen + Σ qty), diisi dengan `SET LOCAL session_replication_role = replica` (tanpa trigger → harga_list/status/total/audit tidak tersentuh). FE: judul "N set · nama · 1 set = … · @harga/set" di form SP (qty roda terkunci di SP dari PO), detail SP (+ terkirim x/y pcs, batal), Minta ubah SP (penanda ikut terkirim), Double Check Vonny, Pengiriman bertahap, laci harga GM; "set (sudah diubah)" bila isi tak sesuai; SP manual: set yang diubah susunannya kembali jadi baris biasa; kolom set hanya dikirim bila ada baris set (SP tanpa set tetap jalan sebelum berkas 126) | **selesai (DB 126 + FE)**; uji DEV rollback: pencocokan 5 skenario (2 set inline+master, set diubah, produk kembar, biaya di tengah, SP 155), putuskan_ubah 3 skenario (tanpa kunci / eksplisit / nilai aneh); sidik md5 baris & so_ringkas identik, audit_log tak bertambah; layar 35/35 + regresi 231/231 · **Review adversarial** (3 pemeriksa + verifikator per temuan, 7 terkonfirmasi, semuanya diperbaiki): pengisi data lama dijadikan fungsi `tandai_set_sp_lama()` dengan pencocokan BERJANGKAR (dulu bisa menandai roda lepas yang kebetulan sama) + menyalin penanda ke nilai_lama usulan SP yang masih menunggu, `revoke` kedua fungsi dari public/anon/authenticated (DEV: migrasi `126b_set_di_sp_perbaikan`); harga per set = nett + EHC (= harga set PO, "termasuk EHC"); SP manual: set yang qty-nya salah ketik tampil "sudah diubah" dan baru dilepas saat disimpan, qty semua roda × bulat → jumlah set ikut; laci GM tidak lagi ketumpahan jawaban lambat dari SP lain (juga konteks HPP). Uji DEV rollback 10 skenario pencocokan; layar 46/46 |
| 58 | Grup pelanggan (usulan 7 Okt; 8 Okt: PO dikirim masing-masing divisi). **Berkas 132**: tabel `customer_groups` (nama, nama_dokumen = induk di dokumen, catatan; RLS baca boleh_baca, tulis hanya lewat RPC), `customers.grup_id` (trigger `customers_jaga_grup`: hanya owner/GM), `quotes.kepada_grup` (judul "<induk> — Divisi <pelanggan>", dihitung trigger `quotes_judul_grup` dari `judul_grup_pelanggan()` — isian bebas REST tidak dipakai; induk sendiri → null), `simpan_penawaran` + `p_kepala.ke_grup`, RPC `daftar_grup_pelanggan` (anggota & pemegang untuk semua peran baca; owner/GM + jumlah SP, penjualan, tahun ini, piutang per anggota), `simpan_grup_pelanggan`, `atur_anggota_grup` (owner/GM; pindah grup = keluarkan dulu). FE: tab Pelanggan › "Grup pelanggan" (kartu per grup, total grup, + Grup baru / Ubah / + Anggota / Keluarkan untuk owner/GM), info grup di laci pelanggan & form penawaran, kotak "Tujukan dokumen ke …" (pratinjau/detail/daftar/salin), GALAT_BERKAS 132 | **selesai (DB 132 + FE)**; uji DEV rollback G1–G9 (owner/sales/Vonny, REST PATCH ditolak, judul dihitung DB); layar 22/22 + regresi 13 berkas · **Review adversarial** (2 pemeriksa + verifikator, 4 terkonfirmasi, diperbaiki): `judul_grup_pelanggan` hanya menjawab peran baca (akun pending/nonaktif dulu bisa membaca nama anggota; DEV `132b_judul_grup_peran`); data grup ditarik segar saat pelanggan dipilih di penawaran, laci pelanggan dibuka, dan muat ulang diam (dulu cache [] menyembunyikan grup yang dibuat belakangan); muat ulang tampilan grup tidak lagi bergantung pada daftar pelanggan; pencarian penawaran ikut judul grup. Layar 25/25 + regresi |
| 59 | Form penawaran menawarkan "+ Pakai … sebagai item baru"; item diusulkan (`usulkan_produk`) saat penawaran disimpan, lalu disahkan owner/GM/staff; dokumen tanpa "(usulan)" · **Opsi B (keputusan Hannes 7 Okt) — berkas 127**: view `usulan_produk` menyembunyikan usulan yang HANYA dipakai di penawaran (belum di PO/SP); usulan dari PO/SP & usulan tak terpakai tetap tampil seperti dulu (kolom, akun_disetujui, pemilik view tidak berubah). FE: form PO/SP/penawaran menawarkan "Pakai usulan yang sudah ada" yang cocok dengan ketikan (teks persis → tanpa tawaran item baru), antrean berjudul "Usulan item dari PO/SP" + catatan penawaran. Pertanyaan tombol "Buang" gugur (usulan penawaran tak jadi order tidak pernah masuk antrean) · **Review adversarial** (7 temuan terkonfirmasi, diperbaiki): usulan dari penawaran dibuat DI DALAM `simpan_penawaran` (p_baris.usulan_teks — gagal simpan tidak meninggalkan usulan yatim di antrean; DEV `129b_usulan_atomik`); `qty_diminta` tidak lagi berlipat (subquery skalar; DEV `127b_usulan_perbaikan`); `usulkan_produk` mengembalikan produk SAH bila teksnya = teks usulan asal / kode produk sah (dulu gagal products_kode_uniq / usulan dobel; produk sah nonaktif → pesan jelas); cek "teks sama" memakai seluruh PRODUK, keterangan produk nonaktif tetap tampil, produk sah ditemukan dari teks usulan asalnya | **selesai (DB 127 + FE)**; uji DEV rollback (penawaran → tersembunyi, PO → tampil dg hitungan, teks beda huruf → usulan sama, atomik, sah/nonaktif, qty 282 bukan 564); layar 16/16 + regresi |
| 60 | Penawaran: UP, e-mail, TOP, diskon per baris (keputusan Hannes 7 Okt). **Berkas 129**: `customers.email` (+CHECK), `quotes.up/email/top` (+CHECK), `quote_lines.diskon/diskon_tipe` dengan CHECK sama persis po_lines (dijaga di tabel — sales bisa menulis lewat REST), trigger `quotes_jaga_top` (sales cash-only → TOP Cash; INSERT & UPDATE OF top, sales_rep_id), trigger `quotes_kontak_pelanggan` (AFTER INSERT, security definer: PIC/e-mail pelanggan yang masih kosong diisi dari penawaran — juga untuk Vonny & pelanggan baru), `simpan_penawaran` menerima kolom baru + pesan galat diskon per baris dari nama constraint. FE: kotak UP & e-mail (otomatis dari pelanggan), TOP (pilihan + Lainnya; terkunci Cash untuk sales cash-only), diskon Rp/% per baris (barang & set), total/PPN/DPP/bawah-list sesudah diskon, dokumen (UP, E-mail, TOP, kolom Diskon), salin penawaran, e-mail di form Pelanggan | **selesai (DB 129 + FE)**; uji DEV rollback 13 skenario (sales/Vonny/owner; diskon %/Rp sah & ditolak, e-mail salah, Riksa tempo ditolak / kosong → Cash, REST diskon & TOP ditolak, PIC tidak ditimpa, 18 baris lama diskon 0); layar 28/28 + regresi · **Review adversarial** (3 pemeriksa + verifikator per temuan, 8 terkonfirmasi — semuanya FE, diperbaiki): persen diskon di dokumen ditulis 4 desimal (dulu "33,33%" untuk 33,3333% sehingga tak cocok dengan Jumlah); cek potongan % habis-sen kini EKSAK dengan bilangan bulat (`persenHabisSen`, juga form PO — dulu toleransi relatif meloloskan potongan puluhan juta yang lalu ditolak DB); ganti tipe % → Rp membulatkan ke sen + memberi tahu (kotak = nilai tersimpan); baris yang hanya berisi diskon ditegur, bukan dibuang; UP/e-mail OTOMATIS dari pelanggan sebelumnya dibuang saat pelanggan dilepas / "+ Pelanggan baru" / sales diganti (dulu kontak PT A tercetak & menempel permanen ke pelanggan baru lewat trigger); salin penawaran: kontak salinan diganti bila perusahaan diganti, penawaran lama tanpa UP/e-mail diisi dari data pelanggan; pratinjau membekukan UP/e-mail/TOP (yang disimpan = yang tampil); form Pelanggan sebelum berkas 129: kotak e-mail terkunci & tidak dikirim (dulu seluruh simpan gagal) + petunjuk berkas. Layar 28/28 (temuan) + regresi 11 berkas |
| 61 | → dikerjakan sesi EHC/komisi (dikonfirmasi Hannes 7 Okt) | sesi EHC |

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
  disimpan (pesan tanpa nama pelanggan/sales lain, minta pilih dari daftar). → **selesai (berkas 131 + FE, 8 Okt)**, lihat
  "#50/#51 lanjutan" di bawah.
- #51 lanjutan: harga khusus hanya berlaku bila harganya DI BAWAH price list (di atas list kembali ke tier); Riksa & Michael
  tetap masuk antrean GM untuk harga di bawah list (komisi tetap flat 1%); penggolongan baris DIBEKUKAN (price list / harga
  khusus yang disahkan sesudah SP dibuat tidak mengubah komisi/gerbang SP itu). → **selesai (berkas 130 + FE, 8 Okt)**.

### #50/#51 lanjutan (8 Okt) — berkas 130 & 131 (DEV sudah) + FE
- **Berkas 130** (#51): `so_baris_hitung` — harga_list BEKU (tanpa cadangan harga_berlaku hari ini), harga khusus dibaca
  per saat SP dibuat dari `harga_khusus_log` (kecuali yang diajukan dari SP itu: per saat pertama disetujui) dan hanya bila
  harga DPP < list, kolom baru `perlu_gm` (non-flat = pct IS NULL; flat bukan Office: di bawah list & tak ditutup harga
  khusus). `so_ringkas` & `antrean_gm` hanya predikat `b.pct IS NULL` → `b.perlu_gm` (replace pada definisi hidup).
  Trigger `sol_zz_list_beku`: UPDATE tanpa ganti produk mempertahankan harga_list (juga kosong); INSERT/ganti produk →
  price list per saat SP dibuat (berlaku tgl SP & dibuat ≤ SP dibuat); INSERT dari putuskan_ubah membawa harga_list lama
  (nilai_lama). `pratinjau_komisi_sp` ikut (+ `perlu_gm`, `n_flat_gm`). Status tersimpan dihitung ulang.
  DEV: 018/IX & 011/X (di gudang) → **menunggu gm** (komisi 562.520 & 17.440 → menunggu GM); 008/X tetap 3% (harga
  khusus dari SP-nya); 003/IX (Michael) gerbang flat tapi harga sudah disetujui. Uji DEV rollback 11 skenario (S1–S8b).
  Sesi EHC sudah diberi tahu (bangun ulang so_baris_hitung dari DEV sesudah 130 untuk #54).
- **Berkas 131** (#50): `jaga_hp_sp_tanpa_pelanggan` + alamat wajib & No. HP milik pelanggan di data pelanggan ditolak
  (SP tanpa PO; pesan tanpa nama), kolom pemicu + alamat; RPC `hp_terdaftar` (ya/tidak). Uji DEV rollback T1–T10.
- FE: label & validasi alamat, cek HP terdaftar saat mengetik & sebelum nomor SP diambil, Minta ubah SP; pratinjau
  komisi flat "menunggu persetujuan harga GM", laci GM tanpa persen untuk SP sales flat, kolom Komisi Anda (flat),
  teks aturan harga khusus. Layar 22/22 + regresi.
- **Review adversarial** (4 pemeriksa + verifikator per temuan; 15 terkonfirmasi, semuanya diperbaiki — DEV:
  `130b_komisi_beku_perbaikan`, `131b_alamat_hp_perbaikan`; berkas 130/131 = versi PROD lengkap):
  · [tinggi] patokan beku `sales_orders.dibuat_pada` bisa dikirim sales lewat REST (price list lama / harga khusus yang
    sudah dinonaktifkan dipakai lagi, gerbang GM terlewati) → trigger `so_a_dibuat_kini` mengisi now() saat INSERT
    (impor tanpa sesi apa adanya; owner/GM masih bisa mengubahnya lewat UPDATE — jaga_pembuat_sp);
  · price list yang diubah di tempat (upsert tanggal berlaku sama / edit massal) atau dihapus sesudah SP dibuat →
    `harga_list_pada()` merekonstruksi dari audit_log;
  · gerbang flat tidak surut ke SP yang sudah dikirim (surat jalan / so_kirim); persetujuan flat tanpa persen gugur
    bila sales diganti ke non-flat (`so_zz_flat_gm_gugur`);
  · permintaan harga khusus menunggu hanya menahan SP pengajunya dari antrean 'harga' (antrean_gm + h.so_id = s.id);
    `ajukan_harga_khusus` tidak lagi memindahkan so_id dari SP pengaju pertama; layar SP tidak lagi menjanjikan
    komisi harga khusus untuk permintaan dari SP lain;
  · No. HP "+62 (0)812…" lolos penolakan & bisa membuat pelanggan ganda → `hp_baku` (620→62), trigger
    `customers_hp_baku`, FE hpNormal; alamat berisi enter/tab dianggap kosong (alamat lama "\n" tidak menggagalkan
    Minta ubah — FE juga mengirim alamat yang tidak diubah apa adanya);
  · FE: peringatan form SP untuk sales flat ("surat jalan & klaim menunggu persetujuan harga GM, komisi tetap flat"),
    kolom Komisi Anda untuk SP flat yang harganya ditolak, teks Harga Special ("Dipakai" = riwayat).
  Uji DEV rollback R1–R9; layar 29/29 + regresi 12 berkas (uji_komisi A2 disesuaikan: sales flat kini diberi
  peringatan).
- **Rilis PROD**: 130 & 131 bersama FE. Sebelum 130, jalankan (baca saja) dan kabarkan Hannes:
  1. baris yang harga_list kosong padahal price list sudah ada saat SP dibuat (akan diisi backfill);
  2. baris yang harga_list-nya TERISI dari price list yang dibuat sesudah SP dibuat (temuan review 5 — tidak diubah
     130; SP setara diperlakukan berbeda):
     `select l.id, s.no_sp, s.status, l.harga_list, public.harga_list_pada(l.product_id, s.tanggal, s.dibuat_pada) beku
      from sales_order_lines l join sales_orders s on s.id = l.so_id where l.product_id is not null
      and l.harga_list is not null and l.harga_list is distinct from public.harga_list_pada(l.product_id, s.tanggal, s.dibuat_pada);`
     (jalankan sesudah fungsi harga_list_pada dibuat, mis. dalam transaksi yang dibatalkan);
  3. SP yang akan kembali "menunggu gm" (bandingkan status_sp_hitung sebelum/sesudah) — termasuk SP Riksa/Michael yang
     belum dikirim dengan harga di bawah list & harga_ok kosong, dipisah per status/lunas/diklaim.
  SP yang sudah di gudang bisa tertahan sampai GM memutus.
- 16–19 (harga_ok direset saat baris berubah, Tolak telat, kosongkan gm_pct lama di PROD, klaim pelanggan belum bertuan):
  Hannes minta dijelaskan ulang (7 Okt) → dijawab 8 Okt (di bawah).

## Jawaban Hannes 8 Okt
1. RHAJA: ROLLER PHINOLIQ 1" & 2" H/R (grey rubber) tetap di RHAJA Series — sudah termasuk di berkas 125, tidak ada perubahan.
2. #58: PO dari grup dikirim oleh **masing-masing divisi** → pertanyaan 2b (komisi PO pusat) gugur.
3. (16) SP kembali ke antrean persetujuan harga GM bila sesudah "Minta ubah SP" masih ada baris di bawah / tanpa list →
   dikerjakan sesi EHC/komisi di tahap #54 (sudah diberi tahu 8 Okt).
4. (17) Tombol Tolak pada keputusan invoice telat DIHAPUS; GM mengisi 0% bila tanpa komisi; keputusan telat hanya menulis
   `gm_pct` (dulu "Setujui" telat ikut menulis harga_ok = true, "Tolak" = false) → **selesai (FE)**, layar 5/5, uji DEV
   rollback: SP telat + 0% → keluar antrean telat, komisi_hitung 0, harga_ok tetap.
5. (18) gm_pct lama dikosongkan → **berkas 128** (data): SP belum telat & belum diklaim; persen harga sudah di gm_pct_harga;
   setiap perubahan dicatat di audit_log ('migrasi 128'). DEV: 8 SP; sidik so_ringkas, komisi_hitung, komisi_belum_klaim,
   antrean_gm, status sama sebelum-sesudah. **Diterapkan di DEV 8 Okt.** PROD: dijalankan bersama paket rilis.
6. (19) Pelanggan belum bertuan tetap hanya diklaim lewat PO (dicatat di ATURAN B › Akses).
7. #55: contoh penawaran menyusul dari Hannes.
8. (18) Sisa #8 "PO menyusul + PO buatan sendiri" → **opsi (b): cek Vonny menahan** → **SELESAI berkas 135 (DEV 8 Okt) + FE**:
   kolom penanda `sales_orders.pelanggan_dari_po` (diisi `tautkan_po_sp` saat pelanggan SP yang kosong terisi dari
   pelanggan PO; dijaga `so_jaga_a_pelanggan` — dipaksa false saat INSERT, tak bisa diubah selain lewat tautkan /
   owner/GM/Vonny); `cek_kelayakan_vonny` kode `lampiran_po` (perlu: sales) & `putuskan_vonny_cek` menolak
   meloloskan (semua peran) selama PO itu tanpa lampiran; Tahan tetap bisa. Data lama: SP hidup belum dikirim yang
   pelanggan & PO-nya terisi bersamaan (riwayat audit) diberi penanda tanpa trigger + audit 'migrasi 135' (DEV 0).
   FE: laci cek Vonny membaca ulang lampiran PO saat "Periksa ulang" → tombol "Lihat lampiran PO" muncul tanpa
   menutup laci. Uji DEV rollback T0–T10 (INSERT kirim penanda → dipaksa false; Tempelkan PO → penanda & 'menunggu
   vonny'; PATCH penanda ditolak; pelanggan dipilih sejak dibuat → tanpa penanda; cek → lampiran_po/sales; loloskan
   ditolak; Tahan ok; sales lampirkan_po → cek ok → loloskan → 'di gudang'; GM boleh ubah penanda). Isi fungsi DEV =
   berkas (md5). Layar uji_lampiran 17/17 (desktop + HP 390); regresi uji_vonny 32/32, uji_vonny2 16/16, uji119
   36/36, uji_hp 35/35, uji_set 46/46, uji_nama 12/12, uji_nomor 10/10, uji12 29/29.
   Sisa (dicatat): PO menyusul yang ditempel SESUDAH barang dikirim tidak lewat cek Vonny lagi — praktis hanya SP
   lama yang lolos cek tanpa pelanggan (sejak #37/#50 cek Vonny menautkan pelanggan, jadi Tempelkan PO pada SP yang
   sudah berpelanggan beda ditolak). SP dari PO biasa (bukan menyusul) tanpa lampiran tetap bisa diloloskan seperti
   sebelumnya; Vonny melihat "belum ada lampiran PO" di laci.
   **Review adversarial 135** (2 pemeriksa + verifikator; 6 terkonfirmasi, 1 dibantah — DEV `135b`): (1) Tempelkan PO
   oleh Vonny/GM/owner tidak menggugurkan cek yang sudah lolos (sp_vonny_gugur_kepala melewati peran pemeriksa; DEV ada
   kandidat nyata SP 44 016/MCE/IX) → `tautkan_po_sp` sendiri memanggil `gugurkan_cek_vonny` bila penanda baru terpasang
   & PO tanpa lampiran; (2) pesan sukses dulu "Invoice sudah boleh diterbitkan" → kini memberi tahu SP menunggu
   lampiran; (3) pesan lampiran_po menyebut pemegang PO (atau owner/GM/staff bila PO tanpa sales), bukan sales SP;
   (4) data lama: SP batal ikut ditandai, SP bertanda yang sudah lolos cek & belum dikirim & PO tanpa lampiran
   dikembalikan ke Double Check (gugurkan_cek_vonny dengan trigger); (5) laci cek Vonny basi bila PO ditempel sesudah
   daftar dimuat (kotak PO & tombol lampiran tak pernah muncul, kotak HP/alamat & catatan PO menyusul basi) → laci
   membaca ulang baris SP saat dibuka & "Periksa ulang" dan digambar ulang bila PO/pelanggan/lampiran berubah;
   (6) baca ulang tidak lagi saat mengetik No. HP/alamat. Isi fungsi DEV = berkas (md5). Uji DEV rollback: Vonny & GM
   menempel PO ke SP yang sudah lolos tanpa pelanggan → vonny_ok kosong, 'menunggu vonny', pesan lampiran; cek
   menyebut "Sales Arie (pemegang PO) atau owner/GM/staff"; PO tanpa sales → owner/GM/staff; pesan putuskan; isi data
   lama → ditandai & digugurkan; PO berlampiran → pesan biasa, cek ok. Layar uji_lampiran 23/23 (+ baris basi,
   tidak menggambar ulang berulang); regresi uji_vonny 32/32, uji_vonny2 16/16, uji119 36/36, uji_hp 35/35,
   uji_nama 12/12, uji_segar 34/34.
   **Cek PROD sebelum rilis 135** (baca-saja; laporkan hasilnya ke Hannes/GM):
   ```sql
   select s.id, s.no_sp, sr.nama sales, s.batal, s.vonny_ok, s.no_surat_jalan,
          exists (select 1 from public.so_kirim k where k.so_id = s.id) dikirim, p.no_po, p.lampiran is not null ada_lampiran,
          a.pada, a.oleh_email
     from public.sales_orders s
     join public.audit_log a on a.tabel = 'sales_orders' and a.aksi = 'UPDATE' and a.baris_id = s.id
          and (a.sebelum->>'customer_id') is null and (a.sesudah->>'customer_id') is not null
          and (a.sebelum->>'po_id') is null and (a.sesudah->>'po_id') is not null
     left join public.purchase_orders p on p.id = s.po_id
     left join public.sales_reps sr on sr.id = s.sales_rep_id
    order by a.pada;
   -- Tempelkan PO yang terjadi SEBELUM audit_log sales_orders mulai mencatat tidak terdeteksi (DEV: audit mulai 10 Sep).
   ```

## Jawaban Hannes 9 Okt — "semua ikut rekomendasi" (daftar keputusan 1–17, 19–20)
- **1–3** (#50/#51): biarkan — harga khusus yang menunggu hanya menutup SP pengajunya; Riksa/Michael: barang tanpa price
  list tidak ditahan; SP lama mereka yang barangnya sudah keluar tidak ditahan ulang.
- **4** (rilis 130): (a) diterima — SEBELUM rilis PROD saya kirim daftar SP yang kembali "menunggu gm" (cek PROD di
  catatan rilis 130: harga_list kosong / list dari pengesahan sesudah SP dibuat / SP yang akan 'menunggu gm').
- **5** (#1): (a) tutup yang langsung terbaca (angka komisi jadi, klaim komisi + rekening + lampiran); catat di ATURAN
  bahwa komisi tetap bisa diperkirakan dari harga oleh peran yang melihat harga SP. **6**: rekening sales di klaim
  komisi ditutup untuk staff & Lenni. **7**: objek milik sesi EHC dikerjakan dengan sepengetahuan sesi EHC.
- **8** (#2): (a) nama sama ditolak untuk SALES di semua jalur (beri pembeda); owner/GM/staff boleh dengan peringatan.
  **9**: ganti nama pelanggan yang punya SP/PO/penawaran/harga khusus hanya owner/GM/staff; sales hanya merapikan
  penulisan; ubahan sales tidak mengisi nama_lama; perubahan data pelanggan dicatat di audit (menutup sisa #8).
  **10**: (a) cek Vonny mendahulukan kembaran milik sales SP; ditahan bila ada kembaran milik sales lain.
  **17**: (a) pelanggan belum bertuan hanya diambil lewat PO, atau dipindah owner/GM/staff.
- **11** (#3): staff baru melihat usulan item dari SP "menunggu cek Vonny" sesudah dicek Vonny.
- **12–13** (#4): baris & kepala penawaran tersimpan dikunci untuk semua peran; penawaran kosong tak bisa dibuat di
  luar layar.
- **14–16** (#7): SP pelanggan daftar hitam ditahan total; daftar hitam & "konfirmasi sebelum kirim" hanya owner & GM
  (staff tidak); invoice & pelunasan barang yang sudah keluar tetap boleh.
- **19**: barang baru lewat Minta ubah SP tetap memakai list tanggal SP. **20**: tanggal/nomor SP tetap UTC.
- Urutan kerja: #3 → #4 → #2 (+9, 10, 17) → #7 → #1.

## Temuan keamanan & bug — DIKERJAKAN DI AKHIR (keputusan Hannes 6 Okt)
Dari uji 50–61 (terbukti di DEV dalam transaksi yang dibatalkan):
1. **Komisi terbaca lewat REST oleh peran yang layarnya menyembunyikan**: Vonny membaca `so_ringkas.komisi` 54 SP
   (Rp 18.550.689,70) dan `komisi_belum_klaim` 51 baris; kemungkinan juga Lie Sian/Ichi/Lenni.
2. **Nama pelanggan ganda**: sales bisa PATCH nama pelanggannya jadi persis nama pelanggan sales lain, dan POST
   `/customers` dengan nama ganda lolos (hanya `buat_pelanggan_baru` yang menolak). Uji: Iwan → "PT Garuda Metalindo".
   → **SELESAI berkas 138 (DEV 9 Okt)** + FE — keputusan 8a, 9, 10a, 17a (menutup juga sisa (1) review 134):
   `customers_tolak_nama_ganda` (BEFORE INSERT/UPDATE OF nama, nama_lama, id; sesudah customers_rapi_nama): id tidak
   bisa diubah (22023); ganti nama pelanggan yang ada di SP/PO/penawaran/harga khusus oleh selain owner/GM/staff ditolak
   bila sidik huruf atau kunci nama berubah (P0001 — merapikan penulisan tetap boleh); SALES: kunci nama BARU (nama &
   nama_lama) yang sama dengan pelanggan lain ditolak (23505, advisory lock per kunci; pesan menyebut pelanggan &
   pemegangnya — boleh dilihat sales, #49). `customers_rapi_nama`: ubahan nama oleh sales tidak mengisi nama_lama.
   `customers_jaga_sales`: sales mengambil pelanggan belum bertuan hanya lewat PO (`po_auto_klaim_sales` memasang
   bendera transaksi `rhj.klaim_po`). Audit `zz_audit_customers` → `catat_perubahan`. `cek_kelayakan_vonny` &
   `lengkapi_pelanggan_sp`: kembaran nama milik sales lain didahulukan, lalu milik sales SP, lalu belum bertuan.
   RPC `nama_pelanggan_kembar(p_nama, p_kecuali)` (boleh_ubah_crm/Vonny; anon dicabut) untuk peringatan layar.
   FE: kotak Sales di laci pelanggan hanya owner/GM/staff (keterangan "milik sales yang pertama membuat PO"), catatan
   ganti nama untuk sales, peringatan nama kembar (confirm) untuk owner/GM/staff di tab Pelanggan, CRM, dan Lead baru;
   Lead baru sales yang ditolak karena nama kembar menawarkan "Pakai pelanggan ini" bila pelanggan itu terlihat (RLS
   customers: miliknya / belum bertuan; lead_tambah tetap `pelanggan_saya`). Teks prinsip tab Pelanggan diperbarui.
   Uji DEV rollback T1–T16: Iwan ganti nama pelanggan bertransaksi → P0001; rapikan → boleh; POST kembar pelanggan
   Hendri → 23505; nama unik → ok (rep 5); ganti ke nama kembar → 23505; ubah id → 22023; klaim langsung → P0001;
   klaim lewat PO → rep 5, bendera kosong lagi; nama_lama tetap kosong; Arie ganti nama 1666 (harga khusus) → P0001;
   kembar 956/966 → cek Vonny `nama_sales_lain`, lengkapi → 42501; owner kembar → boleh; RPC kembar → daftar; owner
   ganti nama → ok; audit 8 baris; tanpa sesi → ok. Layar uji_pelanggan 15/15; regresi uji_hp 35/35, uji_set 46/46,
   uji58 25/25, uji_vonny 32/32, uji_vonny2 16/16, uji119 36/36, uji_segar 34/34, uji_segar2 14/14, uji_nomor 10/10,
   uji_nama 12/12, uji_lampiran 23/23, uji_usulan 4/4, uji_pnw 31/31.
   **Sisa (pertanyaan 21, menunggu Hannes):** kembaran nama LAMA yang belum bertuan (termasuk kembaran pelanggan
   Office) masih bisa diambil lewat PO oleh sales lain — PO memilih pelanggan dari daftar, jadi kembarannya tetap
   "pelanggan belum bertuan" biasa. Pilihan: (a) biarkan, owner/GM/staff merapikan kembaran lama dari tab Pelanggan;
   (b) PO ditolak bila pelanggan belum bertuan yang dipilih punya kembaran nama yang sudah bertuan.
   **Cek PROD sebelum rilis 138:** `select to_regprocedure('public.catat_perubahan()') is not null;` (wajib true) dan
   (informasi untuk Hannes) jumlah kunci nama kembar lama: `select count(*) from (select kunci_nama_pelanggan(nama) k
   from customers group by 1 having count(*) > 1) x;`.
3. **View `usulan_produk`** (milik postgres, bukan security_invoker): semua sales membaca seluruh usulan, pembuatnya,
   dan customer PO sales lain.
   → **SELESAI berkas 136 (DEV 9 Okt)** + FE (teks): view `security_invoker = on` (isi/kolom/opsi B sama persis),
   baris: owner/GM/staff semua, peran lain hanya buatannya / dipakai di PO-SP yang boleh ia lihat; anon tanpa hak,
   authenticated hanya SELECT. Uji DEV rollback (data A–G): owner/GM A,B(2 customer, q=7),C,E,G (D & F tersembunyi —
   opsi B); Hendri A; Alfred B(q=3),C; Iwan B(q=4),E,F(0/0),G; Vonny A,B,E,G; staff A,B,C,G(sp=0) — E tersembunyi
   (keputusan 11); Lie Sian kosong; finance A,B; anon ditolak. Layar uji_usulan 4/4, regresi uji59b 16/16.
   Disengaja: `products.usulan_teks/dibuat_oleh` tetap terbaca semua sales (#59). Diketahui: usulan buatan sales X yang
   hanya ada di penawaran sales lain tampil di antrean X dengan 0/0; staff melihat usulan yang hanya dipakai di SP
   menunggu Vonny dengan Dipakai SP 0. **Verifikator:** usulan_produk wajib security_invoker=on & anon tanpa SELECT;
   jangan revoke kolom products.dibuat_oleh.
   **Review adversarial 136** (pemeriksa bocor/fungsi + verifikator; 3 terkonfirmasi, semua di luar view itu sendiri):
   (a, sedang) **136b**: view invoker memindai po_lines/sales_order_lines/quote_lines tanpa indeks product_id di bawah
   RLS → indeks `po_lines_product_idx`, `sol_product_idx`, `quote_lines_product_idx` (DEV rollback 20 usulan: owner
   17 ms, Iwan 21 ms; sebelumnya ±2,5–4 detik) + layar: gagal memuat usulan ditandai ("?" di ubin, catatan di
   antrean), bukan dianggap 0. **136b WAJIB naik bersama 136 ke PROD.** (b, sedang) **136c**: laporan_penjualan
   (produk, kategori, sales, pelanggan), laporan_margin_produk, laporan_margin_sp (SECURITY DEFINER) menghitung SP
   yang menunggu cek Vonny untuk staff/finance/Lie Sian/Ichi/Lenni — melompati aturan baca berkas 83 (finance bahkan
   melihat nomor SP, Kepada, sales-nya) → fungsi `sp_terbaca(...)` (cermin so_baca, di-inline) ditambahkan pada setiap
   pemindaian SP (ganti teks definisi hidup dengan pemeriksaan jangkar); (c, rendah) view `harga_khusus_lengkap` (tanpa
   invoker): no_sp & dipakai_baris dari semua SP → security_invoker = on (isi sama), anon tanpa hak, authenticated
   SELECT. Uji DEV rollback (usulan di SP 168 menunggu vonny): staff/finance/Lie Sian/Ichi/Lenni → laporan produk,
   pelanggan, margin tanpa SP itu, sales rep 9: 7 SP (owner 9); sesudah vonny_ok → terlihat; owner/GM/Vonny tidak
   berubah; harga khusus SP 152: staff/finance/Lenni no_sp kosong & dipakai 0, owner/GM/Vonny 004/MCE/X/2026 & 1.
   Waktu laporan owner ≤ 90 ms. Layar laporan diberi keterangan. **Untuk Hannes (informasi):** angka laporan
   staff/finance/Lie Sian/Ichi/Lenni kini lebih kecil daripada owner/GM selama ada SP menunggu cek Vonny — mengikuti
   aturan berkas 83. Bila finance ingin tetap melihat SP menunggu di laporan margin, itu pengecualian yang perlu
   diputuskan. **Verifikator:** sp_terbaca wajib sama dengan so_baca; harga_khusus_lengkap wajib security_invoker
   (berkas 115 membuatnya ulang tanpa klausa itu — jangan dijalankan ulang sesudah 136c).
4. **`quote_lines` tanpa penjaga baris**: INSERT teks bebas (tanpa product/set) lewat REST lolos — `jaga_jenis_baris`
   tidak terpasang (butuh fungsi baru; quote_lines tidak punya kolom jenis).
   → **SELESAI berkas 137 (DEV 9 Okt)**, desain dikoreksi kritik (cap waktu kepala bisa dipalsukan lewat PATCH quotes;
   GraphQL): trigger `quote_lines_jaga_baris` (BEFORE INSERT: baris hanya di transaksi & oleh pembuat yang sama dengan
   kepala — quotes.dibuat_pada = now() & dibuat_oleh = auth.uid(); wajib produk/set/set inline), hak UPDATE/DELETE/
   TRUNCATE quote_lines **dan quotes** dicabut dari public/anon/authenticated (keputusan 13: kepala juga terkunci;
   menggantikan izin koreksi kepala owner/GM/staff/Vonny berkas 87 — layar tidak memakainya), constraint trigger
   tertunda `quotes_wajib_baris` (penawaran tanpa baris ditolak saat commit), 3 CHECK berkas 87 divalidasi bila data
   bersih (DEV: valid). FE tidak berubah (hanya /rpc/simpan_penawaran). Uji DEV rollback: Iwan simpan_penawaran 3
   baris (produk, usulan, diskon %) lolos + pemeriksaan tertunda; RPC teks bebas → pesan lama; INSERT teks bebas /
   ke penawaran lama / sales lain → ditolak (P0001); UPDATE & hapus baris → 42501; kepala tanpa baris → ditolak;
   Vonny PATCH kepala (termasuk dibuat_pada='now') → 42501; Vonny mewakili Iwan lolos; owner gabung_produk_usulan
   lolos. Regresi layar uji_pnw 31/31, uji60 28/28, uji60b 28/28, uji12 29/29, uji58 25/25, uji59b 16/16.
   **Cek PROD sebelum rilis 137:** (1) `select extname from pg_extension where extname = 'pg_graphql';` — bila aktif:
   layar tidak memakai GraphQL, sarankan dinonaktifkan (sisa: satu request GraphQL bisa membuat kepala + baris sah
   sekaligus, melompati simpan_penawaran tetapi tetap kena bentuk baris/CHECK/RLS); (2) `select count(*) from
   quote_lines where not (qty > 0) or not (harga >= 0) or not (product_id is null or set_id is null);` — bila > 0,
   VALIDATE ditunda otomatis (NOTICE), laporkan; (3) index.html PROD yang baru (menyimpan lewat simpan_penawaran)
   naik bersama paket ini — index.html lama yang POST /quote_lines langsung akan ditolak. harga_list baris penawaran
   tetap kiriman klien (hanya tanda "di bawah list" di arsip; tidak dipakai gerbang).
   **Review adversarial 137** (2 pemeriksa + verifikator; penguncian bertahan di semua serangan — upsert ON CONFLICT,
   INSERT ke penawaran lama, kepala tanpa baris, fungsi definer lain; 1 terkonfirmasi) → **berkas 137b (DEV 9 Okt)**:
   nama barang & satuan baris masih kiriman klien — lewat POST /rpc/simpan_penawaran langsung, baris set/produk bisa
   mencetak nama bebas ("Forklift Toyota 3 ton") dan satuan bebas. `jaga_baris_quote` kini: produk → deskripsi tetap
   hanya bila sama dengan kode / teks usulan (huruf besar-kecil tidak dihitung), selain itu kode; satuan hanya 'pcs'
   atau satuan master; set master → nama set & 'set'; set inline → label dari isinya (label_set_inline, sama dengan
   label layar) & 'set'. Spesifikasi tetap bebas. FE tidak berubah. Uji DEV rollback (Iwan, simpan_penawaran 6 baris):
   set inline palsu → "Set 05 PU 6" (2 rem + 2 mati)"/set; produk 70 palsu + 'lot' → kode/pcs; set master palsu +
   'unit' → "Set Uji 137b"/set; produk 69 sah + spesifikasi → tetap; kode huruf kecil → tetap; usulan → teks usulan.
   **Cek PROD sebelum rilis 137b (informasi):** `select count(*) from quote_lines l join products p on p.id =
   l.product_id where lower(btrim(l.deskripsi)) not in (lower(btrim(p.kode)), lower(btrim(coalesce(p.usulan_teks,
   p.kode))));` — baris lama tidak diubah; salinan penawaran lama (#44) akan memakai kode master.
5. **Total SP lunas bisa naik**: GM bisa PATCH `sales_order_lines.ehc_item` SP tanpa PO yang sudah ber-invoice/lunas
   (SP 150: 1.640.000 → 1.740.000) — `periksa_total_sp` keluar bila SP tanpa PO. (Area #54 — sesi EHC.)
6. **Klaim EHC/komisi** (area #61 — sesi EHC): owner/GM/staff/finance bisa ubah nominal lewat REST
   (`ekn_ubah`/`kkn_ubah`) tanpa hitung ulang kas; owner bisa hapus klaim yang sudah diajukan/ber-batch (langsung
   atau cascade hapus SP); klaim tidak ikut berubah bila EHC SP diubah (SP 007-IX: klaim 20.000, EHC jadi 5.000).
7. **Daftar hitam terlewati** pada SP tanpa PO tanpa pelanggan (`jaga_blacklist_po` hanya di PO) — makin sering bila
   #50 meloloskan SP tanpa tautan.
8. **SP ditautkan sales ke pelanggannya sendiri lewat REST** (RLS so_tambah/so_ubah with_check pelanggan_saya): INSERT/PATCH
   customer_id ke pelanggan milik sendiri tanpa HP diterima — melompati aturan HP (berkas 122) dan penautan Vonny (#37).
   → **SELESAI berkas 134 (DEV 8 Okt)**, desain dikoreksi kritik (PATCH po_id, tautkan_po_sp lintas sales, Kepada
   palsu lewat REST): trigger `so_jaga_pelanggan` (`jaga_pelanggan_sp_sales`, BEFORE INSERT / UPDATE OF customer_id,
   po_id, kepada; selain owner/GM/Vonny & tanpa sesi) — INSERT dari PO: pelanggan = pelanggan PO (kosong → diisi), PO
   belum tertaut + pelanggan → tolak, sales hanya PO miliknya (jawaban "PO tidak ditemukan"); SP tanpa PO berpelanggan:
   Kepada = nama/nama_lama pelanggan (`kunci_nama_pelanggan`); UPDATE: po_id & customer_id hanya lewat `tautkan_po_sp`
   (bendera transaksi `rhj.tautkan_po`, hanya SP yang belum ber-PO, pelanggan kosong → pelanggan PO). `tautkan_po_sp`:
   sales hanya SP miliknya ("SP tidak ditemukan", sebelum pesan yang menyebut isi SP). FE tidak berubah (tidak ada PATCH
   customer_id/po_id/kepada; form memilih pelanggan → Kepada = nama). Uji DEV rollback: serangan K1–K10 ditolak (PATCH
   pelanggan SP61/157/163, lepas/ganti PO, INSERT PO belum tertaut + pelanggan, INSERT PO sales lain, INSERT 1666 +
   Kepada "Bp Uji Delapan", ubah Kepada SP berpelanggan, tautkan PO ke SP Iwan, staff); sah L1–L7 diterima (pilih
   pelanggan tanpa HP, nama lama, dari PO belum tertaut, dari PO tertaut → diisi, PO menyusul + Tempelkan PO →
   pelanggan terisi & bendera kosong lagi, Vonny lengkapi → 3813, GM ganti, PATCH nilai sama).
   **Sisa → DIPUTUS Hannes 8 Okt: opsi (b), SELESAI berkas 135 (lihat bawah).** Dulu: lewat alur sah "PO menyusul", sales bisa membuat PO untuk
   pelanggan berharga khusus dengan total sama lalu Tempelkan PO → baris 'menunggu gm' pindah ke harga khusus pelanggan
   itu (uji L4: menunggu gm → menunggu vonny). Penjaganya kini hanya PO/lampiran yang dilihat Vonny. Opsi: (a) pelanggan
   patokan harga khusus dibekukan saat SP dibuat (so_baris_hitung — area komisi, perlu sesi EHC); (b) cek Vonny menahan
   SP yang pelanggannya datang dari PO menyusul bila PO-nya tanpa lampiran.
   **Review adversarial 134** (2 pemeriksa + verifikator per temuan; 4 terkonfirmasi — DEV `134b`):
   (1, tinggi — DITUTUP berkas 138, lihat butir 2) sales bisa mengganti nama pelanggannya sementara (UI biasa: ubah
   nama → buat SP pilih pelanggan itu dengan Kepada nama palsu → kembalikan nama), atau menanam alias permanen di
   nama_lama (customers_rapi_nama mengisi nama_lama dari ketikan saat nama_lama kosong & nama dirapikan; tak bisa
   dihapus lewat REST) → Kepada lolos, harga khusus pelanggan itu dipakai, gerbang GM & cek HP/alamat Vonny terlewati;
   alias juga menyetir pencocokan nama Vonny (#37). DEV: 733 pelanggan nama_lama kosong, 2.678 belum bertuan (bisa
   diganti namanya oleh semua sales), 3 pelanggan berharga khusus; customers tidak punya audit_log. Usul (menunggu
   jawaban pertanyaan 9): ganti nama pelanggan yang punya transaksi / harga khusus hanya owner/GM/staff, nama_lama
   tidak diisi dari ubahan sales, audit_log untuk customers; opsional cek Vonny menahan SP tanpa PO yang Kepada-nya
   ≠ nama pelanggan. (2, sedang) "satu PO satu SP" hanya dijaga tautkan_po_sp — INSERT lewat REST memakai PO yang
   sudah dipakai / PO batal, dan SP batal dihidupkan lagi → dua SP hidup pada satu PO (dikirim, ditagih, dikomisikan
   dua kali) → INSERT menolak PO batal / sudah dipakai (sama dengan po_belum_sp) + indeks unik `so_po_satu_sp`
   (po_id, SP tidak batal; semua jalur & peran; pemeriksaan data ganda sebelum indeks dibuat). (3, rendah) urutan
   trigger membocorkan PO sales lain & pelanggannya lewat pesan jaga_po_menyusul → trigger diganti nama
   `so_jaga_a_pelanggan` (menyala sebelum so_jaga_menyusul): PO sales lain selalu "PO #… tidak ditemukan".
   (4, rendah) nama pelanggan diubah selama form SP terbuka → SP ditolak & nomor hangus → layar membaca ulang nama
   pelanggan sebelum nomor diambil, menyesuaikan Kepada, dan minta simpan lagi; pesan DB menyebut "pilih ulang".
   Uji DEV rollback: PO sales lain + pelanggan lain / PO tak ada → sama "tidak ditemukan"; PO sudah dipakai, PO batal
   ditolak; hidupkan SP lama & GM SP kedua → indeks; PO baru belum dipakai lolos. Layar: uji_nama 12/12 (+ uji_set
   mock nama), regresi uji_hp 35/35, uji_set 46/46, uji12 29/29, uji_komisi 33/33, uji_nomor 10/10, uji_segar 34/34,
   uji_segar2 14/14, uji58 25/25, uji_vonny 32/32, uji_vonny2 16/16, uji119 36/36, uji59b 16/16, uji60b 28/28.
   **Cek PROD sebelum rilis 134:** `select po_id, count(*) from sales_orders where po_id is not null and not batal
   group by 1 having count(*) > 1;` — bila ada baris, migrasi berhenti dengan pesan; laporkan ke Hannes/GM.
9. **Tanggal SP tidak dijaga**: sales bisa INSERT/PATCH `sales_orders.tanggal` mundur (juga SP lunas). Snapshot price list
   (`isi_harga_list`) memakai tanggal itu → tier naik & gerbang GM terlewati (uji: SP tgl 12 Agu 'menunggu vonny' vs hari
   ini 'menunggu gm'). → **SELESAI berkas 133 (DEV 8 Okt)** + FE (tanggal tidak lagi dikirim layar):
   trigger `so_a_tanggal_kini` (`jaga_tanggal_sp`, BEFORE INSERT / UPDATE OF tanggal, no_sp) — selain owner/GM & tanpa
   sesi: tanggal := `(now() at time zone 'UTC')::date` (tidak ikut header `Prefer: timezone`), nomor wajib bentuk baku
   bulan itu dan ≤ `sp_counter.terakhir`; sesudah dibuat tanggal & nomor hanya owner/GM. `nomor_sp_baru(p_tanggal)`:
   p_tanggal hanya dipakai owner/GM. Tidak menyentuh jaga_kolom_sales / putuskan_ubah / objek EHC. Uji DEV rollback 18
   kasus (sales tanggal mundur → list 517.600 'menunggu gm'; TimeZone Kiritimati; nomor VIII / 999 / 0015 / teks / 000
   ditolak; PATCH tanggal & nomor SP lunas ditolak, nilai sama lolos; upsert ditolak; GM PATCH & INSERT bebas lolos;
   tanpa sesi lolos; staff dipaksa & ditolak). Layar: uji_hp 35/35, uji_komisi 33/33, uji_set 46/46, uji12 29/29.
   **Cek PROD sebelum rilis 133** (baca-saja; bila ada baris → laporkan ke Hannes/GM, pembetulan bukan otomatis):
   ```sql
   select s.id, s.no_sp, s.tanggal, a.pada as dicatat_pada, a.oleh_email, pr.peran
     from public.sales_orders s
     join public.audit_log a on a.tabel = 'sales_orders' and a.aksi = 'INSERT' and a.baris_id = s.id
     left join public.profiles pr on pr.id = a.oleh
    where s.tanggal not in ((a.pada at time zone 'UTC')::date, (a.pada at time zone 'Asia/Jakarta')::date)
      and coalesce(pr.peran, '') not in ('owner','gm');
   -- + SP tanpa baris audit INSERT (lebih tua dari audit) ditinjau manual;
   -- + nomor yang bukan bentuk baku: select no_sp from sales_orders where no_sp !~ '^[0-9]{3,}/MCE/[IVX]+/[0-9]{4}$';
   -- + tanggal SP yang pernah DIUBAH oleh selain owner/GM (peran = peran sekarang, bukan saat perubahan):
   select a.baris_id, s.no_sp, a.pada, a.oleh_email, pr.peran, a.sebelum->>'tanggal' lama, a.sesudah->>'tanggal' baru
     from public.audit_log a join public.sales_orders s on s.id = a.baris_id
     left join public.profiles pr on pr.id = a.oleh
    where a.tabel = 'sales_orders' and a.aksi = 'UPDATE'
      and (a.sebelum->>'tanggal') is distinct from (a.sesudah->>'tanggal')
      and coalesce(pr.peran, '') not in ('owner','gm')
    order by a.baris_id, a.pada;
   -- untuk SP yang muncul: cek baris yang harga_list-nya ≠ harga_list_pada(product, tanggal, dibuat_pada) (langkah 2
   -- catatan rilis 130) dan baris yang disisipkan selama tanggalnya mundur.
   ```
   **Review adversarial 133** (2 pemeriksa + verifikator per temuan; 4 terkonfirmasi, 1 dibantah — DEV `133b`):
   (1, tinggi) baris yang ditambahkan BELAKANGAN ke SP lama dibekukan pada list tanggal SP itu — kepala SP kosong dibuat
   dulu (draft, tak masuk antrean mana pun) lalu diisi sesudah list naik, atau baris ditambah ke SP lama yang masih
   terbuka / dibuka lagi dengan PATCH catatan → list lama, gerbang GM terlewati (DEV: 388 @400.000 → list 298.000
   'menunggu vonny' vs SP hari ini 517.600 'menunggu gm') → `jaga_tambah_baris_sp`: selain owner/GM, baris langsung
   hanya oleh pembuat SP ≤ 15 menit sejak SP dibuat (layar mengirim baris tepat sesudah kepala); sesudahnya lewat Minta
   ubah SP. Uji DEV: alur layar lolos, kepala lama / SP lama / orang lain ditolak, staff SP sendiri, GM & tanpa sesi
   lolos. (2) nomor ≥ 1000 terpotong `lpad(…,3)` → `nomor_sp_angka()` (nomor_sp_baru & pemeriksaan). (3) cek PROD
   ditambah perubahan tanggal lewat UPDATE (di atas). (4) SP tersimpan tepat saat bulan UTC berganti → layar mencoba
   ulang sekali dengan nomor baru (uji layar 10/10; regresi uji_hp 35/35, uji_set 46/46, uji12 29/29, uji_komisi 33/33).
   **Sisa yang diterima (rendah):** nomor tidak diikat ke pengambilnya — sales bisa memakai nomor yang sudah dikeluarkan
   untuk orang lain tetapi belum tersimpan (orang itu cukup simpan ulang) atau nomor hangus. Barang BARU lewat Minta ubah
   SP tetap dibekukan pada list tanggal SP (sesuai aturan 130; GM memutus usulannya) — bila ingin list hari ini untuk
   barang baru, itu keputusan Hannes + putuskan_ubah milik sesi EHC.

Bug/data non-keamanan yang dicatat:
- **gm_pct harga vs telat** — DIPISAH di berkas 124 (`gm_pct_harga`). (a) sisa gm_pct lama → SELESAI berkas 128 (8 Okt).
  (b) laci keputusan telat menulis harga_ok → SELESAI (FE 8 Okt: tanpa Tolak, hanya gm_pct).
  (c) Untuk SP telat komisi_hitung = total × gm_pct sedangkan so_ringkas per baris — laporan_komisi diperbaiki sesi EHC.
- ajukan_ubah tidak memeriksa No. HP SP (hanya trigger saat diterapkan + validasi layar): usulan tak sah dari tab lama/REST
  ditolak saat GM menyetujui dan GM perlu menolaknya manual.
- `harga_ok` tidak direset saat baris SP berubah lewat Minta ubah SP → baris baru di bawah list ikut persen GM lama tanpa
  ditinjau (diambil sesi EHC di tahap #54, putuskan_ubah).
- ~~Penggolongan baris tidak dibekukan~~ → SELESAI berkas 130 (dibekukan saat SP dibuat, keputusan Hannes 7 Okt).
- ~~Harga khusus mengalahkan tier walau harga jual di atas list~~ → SELESAI berkas 130 (hanya di bawah list).
- ~~Riksa/Michael (flat): baris di bawah list tidak masuk antrean GM~~ → SELESAI berkas 130 (masuk gerbang, komisi tetap flat).
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
