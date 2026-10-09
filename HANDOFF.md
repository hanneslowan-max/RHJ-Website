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
- **#51 (7 Okt, sesi 50–61):** sesi itu akan mengubah rumus komisi (`so_baris_hitung` kolom pct dan/atau
  `komisi_hitung`, berkas 12x) — persen GM untuk baris di bawah price list dipakai, + pratinjau komisi untuk sales.
  Sudah dikabari: nominal komisi **beku saat klaim** (`ajukan_klaim_komisi` → `komisi_hitung` → `komisi_klaim_nilai`),
  sedangkan `laporan_komisi.komisi_terhitung` ikut rumus hidup → SP yang sudah diklaim bisa muncul sebagai selisih
  "belum diklaim" palsu bila rumus menggeser angkanya (DEV: klaim #12 SP 010/MCE/X, #13 SP 007/MCE/X). Mereka
  mengirim definisi final sebelum menerapkan; cek terhadap `laporan_komisi` & `ehc_saldo_sp`. **Tahap 5 (#54)
  "persen tetap" harus memakai kolom persen per baris yang sama dengan #51**, bukan jalur kedua di `so_baris_hitung`.
  Definisi final #51 = `db/123-komisi-persen-gm-pratinjau.sql` (branch 50–61): `komisi_pct_baris()`, kolom baru
  `so_baris_hitung.pct_berlaku`/`sumber_pct` (pct lama tetap), `so_ringkas.komisi` dari pct_berlaku, CHECK
  `so_gm_pct_wajar`, RPC `pratinjau_komisi_sp`/`komisi_sp_saya`. Saya tidak keberatan (7 Okt). Untuk #54: tambah
  kolom per baris (mis. `sales_order_lines.komisi_pct_tetap`) sebagai cabang teratas sesudah 'biaya' di CASE
  `pct_berlaku`, `sumber_pct` = 'tetap GM'.
  **Susulan 124 (`db/124-komisi-gm-harga-terpisah.sql`, sudah di DEV 7 Okt):** persen GM untuk keputusan HARGA kini di
  kolom baru `sales_orders.gm_pct_harga` (CHECK 0–0,5; trigger `so_jaga_gm_pct_harga`); `gm_pct` kembali murni persen
  SP telat. `pct_berlaku` = `coalesce(gm_pct_harga, 0)` bila `harga_ok`. Di DEV urutan terapan: 140 lalu 120–124;
  sesudahnya dicek — saldo EHC per SP, kas sales, klaim komisi #12/#13 tidak berubah, 9 fungsi versi 140 utuh.
- **Keputusan Hannes 8 Okt (dikabarkan sesi 50–61):** (16) `harga_ok` **direset** saat baris SP berubah lewat Minta
  ubah — SP kembali ke antrean harga GM bila masih ada baris di bawah/tanpa price list → **tahap #54 sesi ini**
  (`putuskan_ubah`). (17) Tombol "Tolak" pada keputusan telat dihapus (GM isi 0%); laci telat FE dikerjakan sesi
  50–61 — tidak lagi menulis `harga_ok`. (18) `gm_pct` lama dikosongkan untuk SP non-telat tanpa klaim komisi
  (`db/128`, data saja); tidak berdampak ke klaim karena `jaga_gerbang_komisi` hanya mengisi `pct_gm` untuk SP telat.
  (19) Pelanggan belum bertuan tetap hanya diklaim lewat PO. #58: PO grup dikirim per divisi, komisi tetap per divisi.
- **`db/130` (#51 lanjutan, sesi 50–61, sudah di DEV 8 Okt — saldo EHC per SP & kas sales dicek sama):** `so_baris_hitung` + kolom `perlu_gm` (baris yang menahan
  SP di gerbang GM; flat Riksa/Michael juga bila di bawah list beku), `harga_list` hanya dari baris (tanpa fallback
  `harga_berlaku()`), harga khusus dibaca per saat SP dibuat; `so_ringkas.ada_bawah_list/n_*` dari `perlu_gm`;
  `antrean_gm` cabang 'harga' memakai `b.perlu_gm`; trigger baru `sol_zz_list_beku`. **Untuk #54:** bangun
  `so_baris_hitung` dari `pg_get_viewdef` DEV sesudah 130 (pertahankan `perlu_gm` & lateral harga khusus baru);
  gerbang membaca `so_ringkas.ada_bawah_list`.
  Status SP dihitung ulang di 130 (DEV: 018/IX & 011/X kembali 'menunggu gm'). **`db/131`** mengganti
  `jaga_hp_sp_tanpa_pelanggan` (alamat wajib; No. HP milik pelanggan master ditolak pada SP tanpa PO tanpa pelanggan)
  — `putuskan_ubah` yang memperbarui kepala SP ikut diperiksa bila alamat/telp berubah (ingat saat uji #54).
  **130b/131b** (hasil review, sudah di DEV 8 Okt): `perlu_gm` flat hanya untuk SP belum dikirim; `antrean_gm` 'harga'
  menahan hanya SP pengaju harga khusus; trigger baru `so_a_dibuat_kini` & `so_zz_flat_gm_gugur` (sales_orders),
  `customers_hp_baku`; fungsi `harga_list_pada()`. Tidak menyentuh `putuskan_ubah`, `komisi_hitung`,
  `jaga_gerbang_komisi`, objek EHC. **#54: selalu bangun dari definisi DEV terbaru** (`pg_get_viewdef`/`functiondef`).
  **133/134** (sudah di DEV): `so_a_tanggal_kini` — tanggal & no_sp SP hanya owner/GM; `so_jaga_pelanggan` —
  customer_id/po_id SP hanya lewat `tautkan_po_sp` (bila sesi ini membuat ulang `tautkan_po_sp`, bawa bendera
  `rhj.tautkan_po` + batas "sales hanya SP miliknya"). **Tahap komisi:** `ajukan_klaim_komisi` masih memakai
  `current_date` (ikut TimeZone sesi, bisa diatur klien lewat header `Prefer: timezone`) → ganti `hari_ini_wib()`
  (objek 140 sudah memakai `hari_ini_wib()`). **#8 (menunggu Hannes):** bila dipilih "bekukan pelanggan patokan harga
  khusus saat SP dibuat", itu perubahan `so_baris_hitung` di area sesi ini.
  **Susulan (8 Okt):** trigger 134 kini bernama `so_jaga_a_pelanggan`; indeks unik `so_po_satu_sp` (satu PO hanya
  untuk satu SP hidup — berlaku juga untuk fungsi definer); `db/133b` `jaga_tambah_baris_sp` (selain owner/GM dan
  selain `rhj.usul='on'`, baris SP hanya disisipkan pembuat SP ≤ 15 menit sejak dibuat — bawa syarat ini bila
  fungsinya dibuat ulang). **Untuk #54/16 (reset `harga_ok`):** barang BARU lewat Minta ubah dibekukan pada price
  list tanggal SP (aturan 130) → bisa lolos gerbang bila list lama lebih rendah dari list hari ini; putuskan perlakuannya
  saat merancang #54.
- **#57 (8 Okt, sesi 50–61, `db/126`, sudah di DEV):** kolom tampilan set di `sales_order_lines` (`set_grup`,
  `set_nama`, `set_qty`, `set_isi`; CHECK `sol_set_lengkap`; tidak dipakai komisi/gerbang/kirim/batal). `putuskan_ubah`
  **tidak** diubah; sebagai gantinya trigger `sol_set_usul` (BEFORE INSERT, `isi_set_baris_usul()`) mengisi kolom set
  saat `rhj.usul='on'` dari usulan `usul_ubah` yang masih 'menunggu'. **Untuk #54:** `putuskan_ubah` versi baru tidak
  perlu membawa kolom set, asal baris SP tetap diinsert selagi usulan 'menunggu' dan `rhj.usul='on'`. Dicek sesudah 126:
  saldo EHC per SP, kas sales, klaim komisi #12/#13 tidak berubah.
- **Kendala tahap #54:** `putuskan_ubah` memuat `DELETE` → MCP Supabase menggantung untuk `create or replace`-nya
  (dialami kedua sesi). Siapkan berkasnya untuk dijalankan Hannes di SQL Editor DEV (seperti 140b), atau rancang
  ulang tanpa DELETE; uji rollback-nya juga harus tanpa teks "delete" bila lewat MCP.
- **Pekerjaan tertunda sesi ini (tahap komisi):** `laporan_komisi.komisi_terhitung` memakai `so_ringkas.komisi`, padahal klaim
  memakai `komisi_hitung` (SP telat >120 hari = total_barang × gm_pct) → laporan salah untuk SP telat. Ganti ke
  `komisi_hitung(s.id)`. **Tahap #54:** `harga_ok` tidak direset saat baris SP berubah lewat `putuskan_ubah`; dan
  `gm_pct` per SP dipakai bersama keputusan harga & telat (catatan sesi 50–61).

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

### Posisi tahap 1 (selesai 9 Okt)
- **`db/140-ehc-saldo-pemakaian.sql` SUDAH diterapkan di DEV** (`apply_migration 140_ehc_saldo_pemakaian`).
  Sebelumnya diuji utuh dalam transaksi rollback di DEV: **46/46 skenario lulus** (konversi klaim lama, saldo per SP,
  simpan/ubah/batal klaim, lampiran dibuang lunak, hak per peran & RLS, Vonny tidak melihat nominal, gerbang batal
  SP/qty, EHC cepat, ajukan transfer sesudah cutoff, PIC terkunci, rekening PIC ≠ rekening sales, laporan komisi,
  `so_ringkas` tidak berubah). Diperiksa sesudah diterapkan: klaim lama #6/#7 → `diajukan`, periode 2026-10,
  alokasi SP 41 Rp 5.000 & SP 35 Rp 20.000; md5 `so_ringkas` tetap; kas sales 0 baris.
- **`db/140b-ehc-buang-batas-lama.sql` SUDAH dijalankan Hannes di SQL Editor DEV (9 Okt)** — indeks `ehck_so_uniq`
  dan check lama `ehck_cara_bayar_sah` hilang; `ehck_cara_bayar_sah2` tetap.
- **Uji pasca-140b lulus 15/15** (rollback, 9 Okt; scratchpad `uji/uji2.py` → `uji2.sql`): dua klaim pada SP yang sama,
  reimburse menyalin rekening sales (atau kosong bila belum diisi finance), klaim melebihi sisa ditolak per sen, ubah
  sampai pas sisa, batal → saldo kembali, owner membatalkan klaim lama, klaim multi-SP beda customer = lintas & tidak
  bisa EHC cepat, ubah melepas SP → tidak lintas lagi (alokasi 0), log ajukan+ubah tercatat. DEV bersih sesudahnya.
- **TAHAP 1 SELESAI di DEV** (DB 140+140b, layar index.html). PROD belum — ikut paket rilis.
- Layar (index.html) sudah memakai struktur 140; uji Playwright 14/14 (harness di scratchpad `layar/`).
- Catatan teknis MCP Supabase: DROP dan fungsi berisi `DELETE … WHERE` macet → 140 ditulis tanpa DELETE.
  Panggilan besar (>80 KB) kadang terputus di tengah; skrip uji diringkas dengan fungsi bantu `pg_temp.c`/`pg_temp.u`.
- **Fungsi yang ditimpa 140** (sesi 50–61: jangan `create or replace` dari salinan lama — ambil dari DEV):
  `batalkan_baris_sp`, `pulihkan_baris_sp` (cek klaim EHC dibuang), `jaga_rekening_pic` (customer_id ikut
  terkunci), `jaga_gerbang_klaim`, `minta_klaim_cepat`, `ajukan_transfer`, `laporan_komisi`,
  `klaim_ehc_saya`, `ajukan_klaim_ehc`/`ajukan_klaim_ehc_cepat` (dipensiunkan), view `kas_sales`, `ehc_cepat_siap`.
- **Saat merge dengan branch 50–61 (#52 muat ulang diam-diam):** di sana `muatEhc`/`muatKomisi`/`muatGm` diberi
  pola `var awal = X.dimuat;` + di awal `.then` `if (awal && !X.dimuat) { X.memuat = false; SEGAR.dibatalkan++;
  return muatX(); }`, dan registry `MUAT_DIAM` punya entri ehc/komisi/gm (ehc memanggil muatEhc + muatEhcHal +
  cacah — nama fungsi itu tetap ada di versi baru). `muatEhc` versi sesi ini ditulis ulang → pasang ulang pola itu
  saat merge; kas & laporan belum terdaftar di MUAT_DIAM (lihat HANDOFF branch itu, "Catatan #52 untuk sesi lain").
- **Menunggu keputusan Hannes:** (1) isian nominal di HP — titik jadi koma desimal (#45), usul tampilkan
  "terbaca: Rp …"; (2) EHC SP Office/cabang/sales nonaktif tidak pernah tertutup (tahap 4); (3) #54 butuh mekanisme
  "persen tetap" karena EHC bagian dari harga (tahap 5); (4) ~~sales bisa mengganti `customer_id` SP lewat REST~~ —
  **selesai oleh `db/134`** sesi 50–61 (trigger `so_jaga_pelanggan`).
- Tahap berikut yang diusulkan: 3 (periode & pemeriksaan GM) sebelum 2 (kartu kredit), lalu 4, 5, 6.

### Tahap 3 — periode & pemeriksaan GM (mulai 9 Okt)
- Rancangan final: **`RANCANGAN-EHC-TAHAP3.md`** (workflow peta DEV/layar/aturan → 3 rancangan → juri → penyusun).
  Berkas: db/141 (struktur), db/142 (fungsi), db/143 (view antrean_gm & ehc_cepat_siap) — masing-masing < 80 KB,
  tanpa kata delete/drop.
- **Keputusan Hannes 9 Okt:** P1 GM/owner **boleh** memutus klaim yang ia buat/ubah/minta cepat atau milik sales
  yang tertaut ke akunnya (cukup tercatat); P2 tolak EHC cepat = hanya cepatnya ditolak, klaim ikut pemeriksaan biasa;
  P3 ditolak sesudah komisi SP diklaim → saldo ke kas sales; P4 **Vonny/Lie Sian/Ichi tidak melihat klaim EHC**.
- Inti: status diajukan → disetujui/ditolak oleh GM per klaim sesudah cutoff 18 (lintas boleh disetujui GM; massal
  hanya non-lintas); rekening tujuan dikunci saat disetujui (`ehc_klaim_tujuan`); jejak `ehc_klaim_putusan`;
  finance mengunci daftar bayar sekali per periode mulai tgl 20 WIB (`rekap_ehc_bulanan`, hanya SP lunas), transfer,
  keluarkan yang gagal, isi referensi → `ditransfer_pada`; EHC cepat disetujui GM kapan saja, cair sebelum lunas.
  EHC tidak lagi lewat `transfer_pengajuan` (komisi tetap jalur lama sampai tahap 4).
- Urutan: FE prasyarat D1 (formGmPutus ELSE tidak lagi PATCH sales_orders untuk jenis tak dikenal) → 141/142/143 diuji
  rollback lalu diterapkan di DEV → FE D2–D5 + Playwright → ATURAN B + HANDOFF + ALUR-KERJA.
- **DB tahap 3 SUDAH di DEV (9 Okt):** 141_ehc_periksa_gm_struktur, 142_ehc_periksa_gm_fungsi, 143_ehc_periksa_gm_view.
  Workflow: penulis → 3 peninjau (bisnis/keamanan/kompat) + verifikasi skeptis (7 temuan terbukti, diperbaiki) → uji
  rollback DEV **271 skenario/8 skrip lulus** (scratchpad `tahap3/uji/gen3.py` → `uji3-*.sql`; mock lokal PostgreSQL di
  `tahap3/mock/`). Sesudah diterapkan: 6 sidik (so_ringkas, ehc_saldo_sp, kas_sales, komisi_klaim+nilai, laporan_komisi,
  antrean_gm non-EHC) **sama** dengan sebelum; Vonny 0 klaim; hak baca kolom rekening kepala `ehc_klaim` dicabut.
  - **Hak baca `ehc_klaim` kini PER KOLOM** (semua kecuali bank/no_rekening/atas_nama): kolom baru di tahap berikut
    WAJIB `grant select (kolom) on public.ehc_klaim to authenticated`. Rekening dibaca dari `ehc_klaim_tujuan`
    (owner/GM/finance + sales pemilik). Layar EHC versi tahap 1 (EHC_KOLOM memuat bank/no_rekening/atas_nama) **error
    di DEV sampai layar tahap 3 jadi**.
  - RPC baru: `putuskan_klaim_ehc(p_klaim,p_setuju,p_catatan,p_versi)`, `setujui_klaim_ehc_massal(p_daftar)`,
    `rekap_ehc_bulanan(p_bulan)`, `keluarkan_klaim_ehc_batch(p_klaim,p_alasan)`, `ehc_daftar_bayar(p_bulan,p_batch)`,
    `putuskan_klaim_cepat_v(...)` (dengan versi; `putuskan_klaim_cepat` lama tetap untuk layar lama). `ajukan_transfer('ehc')`
    → 0A000. Antrean GM: 'ehc_periksa' (ref_id = −id klaim), 'ehc_dini' dibuang.
- **Layar tahap 3 SELESAI (9 Okt):** workflow pembangun → 3 peninjau + verifikasi skeptis (12 temuan terbukti,
  diperbaiki) → Playwright **31/31 lulus** (skenario tahap 1 + 12–28 tahap 3; 44 sesi, 0 pageerror, 0 request keluar;
  harness scratchpad `layar/`). Uji asap PostgREST DEV dengan kunci publishable (anon): EHC_KOLOM penuh + embed
  `customer_pics!ehc_klaim_pic_id_fkey`/`ehc_klaim_tujuan`/`ehc_klaim_putusan` dan parameter 6 RPC baru dikenali
  (kontrol embed/parameter palsu → PGRST200/202). Isi: laci GM EHC (`formGmPutusEhc`, setujui/tolak, versi, 40001 →
  muat ulang), halaman EHC "Perlu diperiksa GM" (centang massal, lintas/tanpa lampiran tidak bisa), status klaim baru,
  tombol Batalkan GM/owner, Laporan Finance `blokBayarEhc` (kunci daftar/keluarkan/rincian/referensi; Lenni tanpa
  tombol & rekening), EHC emergency + batch cepat, `formGmPutus` ELSE hanya harga/telat, ehc_dini dibuang.
  - Sisa kecil (dicatat, belum dikerjakan): peringatan "menunggu GM" di Laporan Finance baru segar sesudah Rekap
    ditekan ulang; staff boleh membaca klaim EHC tapi tidak punya menu EHC (TAB tetap owner/gm/finance/sales);
    Lenni masih melihat tombol komisi lama (blok komisi sengaja tidak diubah; DB menolaknya); "Minta EHC cepat" masih
    tampil untuk klaim lewat cutoff yang menunggu GM (DB mengizinkan); dua periode (bayar Sept vs rekap Okt) di satu
    layar Laporan; kode mati cabang 'ehc' di loop Batch transfer; nama pelaku riwayat laci = "pengguna lain" bila
    profiles tidak terbaca. **Uji asap per peran dengan login sungguhan di DEV masih perlu (Hannes).**
- **Rilis PROD:** tuntaskan pengajuan EHC lama dengan layar LAMA → migrasi s.d. 141→142→143 → unggah index.html segera.
  Layar baru tidak bisa menuntaskan pengajuan EHC 'disetujui' (tanpa tombol rekap_transfer('ehc')), dan tab/laci EHC-nya
  tidak berfungsi sebelum 141. Rinciannya di `RANCANGAN-EHC-TAHAP3.md` bagian E.
- Koordinasi 9 Okt: sesi 50–61 tidak mengubah `antrean_gm` selama 141–143 dibangun (definisi DEV sudah membawa
  ubahan 130: `b.perlu_gm`, harga khusus `h.so_id = s.id`). **Merge `formGmPutus`:** branch 50–61 mengubahnya di
  0c9e0f1 (persen keputusan HARGA → `gm_pct_harga`, `gm_pct` khusus telat), 7888154 (sales flat → tanpa persen,
  `flatGm`), dan keputusan 8 Okt (telat tanpa Tolak; Setujui telat hanya `gm_pct` + `gm_pada`). Pertahankan ketiganya;
  pembatasan ELSE ke harga/telat + pembuangan cabang ehc_dini dari sesi ini tidak bertentangan. Temuan keamanan #1 di
  sesi itu (klaim komisi/rekening terbaca Vonny dkk.) akan dikoordinasikan sebelum dikerjakan.
- **`db/139k` (sesi 50–61, sudah di DEV 9 Okt, keputusan Hannes 5a/6/7):** angka komisi di `so_baris_hitung`/`so_ringkas`/
  `komisi_belum_klaim`/`cash_belum_cocok` disaring per peran; **event trigger `jaga_view_komisi` menolak CREATE/ALTER
  VIEW keempat view itu tanpa `boleh_lihat_nilai_klaim`** (bawa predikat 139k bila tahap 4/#54 mendefinisikan ulang);
  kolom `bank/no_rekening/atas_nama` `komisi_klaim` tidak terbaca REST → tabel `komisi_klaim_rekening` (owner/GM/finance +
  sales pemilik). Layar branch ini sudah disamakan (KOMISI_KOLOM meng-embed `komisi_klaim_rekening`, `rekKlaimKomisi`,
  teks identik dengan commit 86c00c9 supaya merge bersih). **Untuk tahap 3:** salinan rekening di kepala `ehc_klaim`
  (reimburse = rekening sales) masih terbaca staff/Lenni — samakan dengan prinsip 139k (rekening hanya owner/GM/finance +
  sales pemilik) lewat `ehc_klaim_tujuan` / hak per kolom.

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
