# Rancangan EHC tahap 3 — periode 19–18, pemeriksaan GM per klaim, bayar tgl 20

Disusun 9 Okt 2026 lewat workflow (4 pembaca DEV/layar/aturan → 3 rancangan: hemat 6/5,5 · bersih 7,5/7 · aman 8,5/8 →
2 juri → penyusun final). Sumber kebenaran tetap DEV + berkas db/141–143 sesudah dibuat.

## Keputusan Hannes 9 Okt (jawaban P1–P4) — MENGUBAH rancangan di bawah
- **P1 — GM/owner BOLEH memutus klaim EHC yang ia buat/ubah/minta cepat, atau milik sales yang tertaut ke akunnya.**
  Cukup tercatat siapa yang memutus (gm_oleh + ehc_klaim_putusan). → Buang B1.1 `klaim_ehc_pemutus_terlibat` dan
  semua pemakaiannya (inti, massal, putuskan_klaim_cepat, tombol Setujui di laci GM). Massal tetap mengecualikan lintas.
- **P2 — Tolak EHC cepat = hanya pencairan cepatnya ditolak**; klaim tetap 'diajukan', ikut pemeriksaan GM sesudah tgl 18.
- **P3 — Ditolak sesudah komisi SP diklaim → saldo yang kembali masuk kas sales** (tidak ada perubahan hitungan).
- **P4 — Vonny, Lie Sian, Ichi TIDAK melihat klaim EHC.** Klaim EHC hanya owner, GM, staff, finance, Lenni, dan sales
  pemiliknya → 141 mempersempit hak baca `ehc_klaim` (dan riwayat cepat `ehc_cepat_log`) ke
  `boleh_lihat_nilai_klaim() or klaim_ehc_saya(id)`; cek view `sales_beban` dan layar ketiga peran itu yang membaca
  ehc_klaim (hitungan klaim per sales untuk mereka menjadi 0).

## Rancangan final (penyusun workflow; baca bersama keputusan di atas)

RANCANGAN FINAL TAHAP 3 — EHC: periode 19–18, pemeriksaan GM per klaim, bayar tgl 20

0. DASAR & PILIHAN
- Dasar: rancangan "aman" (juri 8,5/8). Cacat berat dibuang: (1) "kunci = dibayar" tanpa jalan mundur → kunci → transfer → KELUARKAN yang gagal → isi referensi; "ditransfer" baru sesudah referensi (ditransfer_pada); (2) penyempitan hak baca Vonny/Lie Sian/Ichi menunggu P4; (3) cakupan larangan memutus klaim sendiri menunggu P1, terkumpul di SATU fungsi; (4) daftar bayar terbaca Lenni, rekening hanya owner/GM/finance; (5) p_versi dikirim FE apa adanya (string PostgREST); (6) massal melaporkan hasil per klaim, bukan all-or-nothing.
- Dicangkok: ref_id negatif 'ehc_periksa' (hemat); gerbang periode_bayar + advisory lock + indeks unik; jaga_batch dikeraskan, hitungan menunggu_lunas/menunggu_gm/tanpa_rekening (bersih); rekap_ehc_cepat tanpa DELETE, WIB. Tidak dipakai: pengecualian lampiran "warisan", FK cascade, finance menyalin rekening ke header, menggeser arti transfer_pengajuan. simpan_klaim_ehc (#61) tidak disentuh.
- Dicek ulang di DEV 9 Okt: batalkan_klaim_ehc menolak cepat yang disetujui; rekap_transfer cabang ehc tak memeriksa status; jaga_batch tak menjaga dibuat_*/ref_*; formGmPutus ELSE (14192–14199) PATCH /sales_orders; hanya simpan_klaim_ehc menulis alokasi/berkas (mengisi diubah_pada); data #6/#7 diajukan 2026-10 tanpa berkas; pengajuan/batch/ehc_dini_minta = 0.

A. MODEL DATA (db/141)
A1. ehc_klaim — kolom baru: gm_oleh uuid REFERENCES auth.users(id) (tanpa klausa hapus), gm_pada timestamptz, gm_catatan text, gm_jalur text, ditransfer_pada timestamptz.
- CHECK: ehck_gm_jalur_sah (null|periksa|cepat|konversi); ehck_putusan_lengkap (status disetujui/ditolak ⇒ gm_pada & gm_jalur terisi); ehck_tolak_beralasan (ditolak ⇒ gm_catatan terisi); ehck_bayar_disetujui (batch terisi ⇒ status 'disetujui'); ehck_ditransfer_berbatch (ditransfer_pada ⇒ batch terisi).
- Indeks ehck_periksa_idx(periode) WHERE status='diajukan' AND transfer_batch_id IS NULL.
- Status tetap 4 nilai: diajukan (≤ cutoff bisa diubah; sesudahnya menunggu GM), disetujui (diputus GM: periksa/cepat/konversi), ditolak (final, saldo kembali), batal. transfer_batch_id = masuk daftar bayar; ditransfer_pada = referensi bank terisi = uang keluar.

A2. BARU ehc_klaim_tujuan — rekening tujuan yang DIKUNCI saat GM setuju; satu baris per klaim.
- Kolom: klaim_id bigint PK REFERENCES ehc_klaim(id); sumber CHECK (pic|sales|tunai); pic_id; bank; no_rekening; atas_nama; dikunci_oleh uuid REFERENCES auth.users(id); dikunci_pada timestamptz default now(). CHECK: tunai ⇔ tanpa rekening, selain itu bank & no_rekening wajib.
- RLS ekt_baca: SELECT authenticated USING (peran_saya() in ('owner','gm','finance') OR klaim_ehc_saya(klaim_id)) — setara srr_baca, rekening sales tidak bocor ke staff/Lenni/Vonny. Tanpa policy tulis; revoke public/anon, grant select; trigger ekt_tetap (BEFORE UPDATE → raise) + zz_audit catat_perubahan().

A3. BARU ehc_klaim_putusan — jejak append-only.
- Kolom: id bigserial PK; klaim_id REFERENCES ehc_klaim(id); jalur CHECK (periksa|cepat|konversi|bayar); aksi CHECK (setuju|tolak|keluar_batch); catatan; snapshot jsonb NOT NULL default '{}'; oleh uuid REFERENCES auth.users(id); pada timestamptz default now(). CHECK ekp_beralasan (aksi ≠ setuju ⇒ catatan terisi). Indeks unik parsial ekp_setuju_uniq(klaim_id) WHERE aksi='setuju'; ekp_klaim_idx.
- snapshot: versi, nominal, alokasi[{so_id, no_sp, nominal, lunas, batal, total_ehc, terpakai, tertutup}], lintas, customer_id, keperluan, cara_bayar, tujuan {sumber, pic_id} (tanpa nomor rekening), berkas[{id, path}], cepat_alasan.
- RLS ekp_baca: boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id); tanpa policy tulis; revoke; ekp_tetap; zz_audit. Tabel baru karena melebarkan CHECK ehc_klaim_log butuh DROP CONSTRAINT; ehc_klaim_log & ehc_cepat_log tetap dipakai.

A4. transfer_batch
- Kolom baru periode_bayar text (null atau ^YYYY-MM$). Unik parsial tb_ehc_periode_uniq (jenis, periode_bayar) WHERE periode_bayar IS NOT NULL AND NOT cepat AND jumlah_klaim > 0. Batch yang seluruh isinya dikeluarkan tidak menahan kunci ulang; batch lama (null) tidak kena.
- Batch bulanan: jenis 'ehc', bulan = periode_bayar, cepat=false, tanggal = hari_ini_wib(). Batch cepat: bulan WIB, periode_bayar null.

A5. Bantu periode_bayar_ehc(date) IMMUTABLE: tgl ≥20 → bulan itu; selain itu bulan lalu (9 Okt → 2026-09; 20 Okt → 2026-10).

A6. Tidak berubah: transfer_pengajuan(+_baris) ('ehc' tetap sah untuk riwayat), komisi_*, ehc_saldo_sp, kas_sales, laporan_komisi, kolom ehc_dini_*. Tahap 2: kartu_kredit lewat mesin status yang sama; tolak kartu kredit → potongan komisi merujuk ehc_klaim_putusan.id.

B. FUNGSI
Umum: SECURITY DEFINER, search_path=public, dibangun dari pg_get_functiondef DEV saat diterapkan, teks tanpa kata delete/drop (juga komentar, "on delete", "dropdown"); revoke public/anon, EXECUTE authenticated hanya RPC. Galat: 42501 hak, 22023 keadaan, P0002 tidak ada, 40001 versi basi/daftar berubah, 23514 saldo, 0A000 jalur pensiun. Urutan kunci: klaim (id naik) → SP (id naik), sama dengan simpan_klaim_ehc.

B1. BARU
1. klaim_ehc_pemutus_terlibat(p_klaim) boolean STABLE, EXECUTE authenticated (FE mematikan tombol). Default (P1) true bila: k.dibuat_oleh = auth.uid(); ATAU ada ehc_klaim_log ajukan/ubah oleh saya; ATAU ada ehc_cepat_log 'minta' oleh saya; ATAU sales_rep klaim tertaut ke akun saya (Hannes ↔ rep 13).
2. siapkan_setuju_klaim_ehc(p_klaim, p_jalur) jsonb — internal; pemanggil sudah FOR UPDATE.
   - Cek: ≥1 berkas aktif ('Klaim tanpa lampiran tidak bisa disetujui — tolak dengan alasan.'); SP alokasi >0 dikunci FOR UPDATE urut id; tidak ada SP batal; tiap SP trunc(so_ringkas.total_ehc,2) ≥ Σ alokasi diajukan/disetujui (23514); Σ alokasi = ehc_klaim_nilai.nominal.
   - Tujuan dibaca SAAT INI: transfer → PIC k.pic_id aktif, milik k.customer_id, rekening terisi, ≠ rekening sales mana pun (normalisasi digit seperti simpan_klaim_ehc); reimburse → sales_rep_rekening(k.sales_rep_id) wajib ('Rekening sales belum diisi finance'); tunai → tanpa rekening; kartu_kredit → 0A000.
   - INSERT ehc_klaim_tujuan; kembalikan snapshot.
3. putuskan_klaim_ehc_inti(p_klaim, p_setuju, p_catatan, p_versi, p_massal) jsonb — internal.
   - Pemeriksaan berurutan: boleh_approve; FOR UPDATE (P0002); pemutus_terlibat → 42501; status ≠ diajukan → 22023; batch terisi → 22023; cepat menunggu → 22023 ('putuskan di antrean EHC cepat'); hari_ini_wib() ≤ cutoff_ehc(periode) → 22023 ('diperiksa sesudah tgl 18; mendesak → EHC cepat'); p_versi null atau ≠ coalesce(diubah_pada, dibuat_pada) → 40001 ('klaim berubah, muat ulang'); tolak tanpa catatan → 22023; p_massal & klaim_ehc_lintas → 22023.
   - Setuju: siapkan_setuju('periksa') lalu status 'disetujui' + gm_oleh/gm_pada/gm_catatan, gm_jalur 'periksa'. Tolak: status 'ditolak' + gm_*. Keduanya INSERT putusan (periksa); cepat_* tidak disentuh.
4. RPC putuskan_klaim_ehc(p_klaim, p_setuju, p_catatan default null, p_versi timestamptz default null) text = inti(…, false).
   - Pesan: 'DISETUJUI. Dibayar finance mulai tgl 20 begitu semua SP lunas[; SP x belum lunas]' / 'DITOLAK. Saldo Rp… kembali ke SP …[; SP tertutup komisi → kas sales]'.
5. RPC setujui_klaim_ehc_massal(p_daftar jsonb) jsonb.
   - boleh_approve; isi 1–100 butir [{klaim, versi}] tanpa duplikat; diproses urut id.
   - Per butir: lintas atau pemutus terlibat → dilewati; selain itu BEGIN inti(id, true, null, versi, true) EXCEPTION WHEN others → gagal {klaim, pesan}.
   - Hasil {disetujui:[{klaim, nominal}], dilewati, gagal, total}. Tidak ada tolak massal.
6. RPC rekap_ehc_bulanan(p_bulan) jsonb — "Kunci daftar bayar EHC".
   - boleh_rekap_transfer; format; p_bulan ≠ periode_bayar_ehc(hari_ini_wib()) → 22023 ('yang bisa dikunci hari ini periode %, mulai tgl 20') — gerbang keras: terlambat boleh, periode lama ikut otomatis; pg_advisory_xact_lock(hashtext('rhj.rekap_ehc')); ada batch ehc periode_bayar = p_bulan berisi → 22023 ('sudah dikunci, batch #%').
   - Kandidat = ehc_klaim_siap_transfer(p_bulan), FOR UPDATE urut id, SP FOR SHARE urut id, dihitung ulang. n=0 → jsonb tanpa INSERT.
   - INSERT transfer_batch(jenis 'ehc', bulan, periode_bayar, tanggal hari_ini_wib(), jumlah_klaim, total, cepat false, dibuat_oleh) → rhj.batch on → UPDATE ehc_klaim SET transfer_batch_id WHERE id = any AND batch null AND status 'disetujui' → GET DIAGNOSTICS ≠ n → 40001 → off.
   - Hasil {batch, jumlah, total, menunggu_lunas, menunggu_gm, tanpa_rekening, pesan 'Transfer sesuai daftar; yang gagal keluarkan; lalu isi referensi'}.
7. RPC keluarkan_klaim_ehc_batch(p_klaim, p_alasan) text: boleh_rekap_transfer; alasan wajib; klaim & batch FOR UPDATE; batch harus 'ehc' dan no_referensi null (else 22023 'sudah berreferensi — uang dianggap keluar'). rhj.batch on: klaim batch → null; batch jumlah−1, total−nominal; putusan (bayar, keluar_batch). Klaim tetap 'disetujui': bulanan ikut tgl 20 berikutnya, cepat kembali ke EHC emergency.
8. RPC ehc_daftar_bayar(p_bulan text, p_batch bigint default null) RETURNS TABLE(klaim_id, keadaan, periode, sales_rep_id, sales, customer, lintas, keperluan, cara_bayar, sumber_tujuan, bank, no_rekening, atas_nama, nominal, sp jsonb, gm_nama, gm_pada, batch_id, ditransfer_pada).
   - Hanya boleh_lihat_nilai_klaim (sales 42501); kolom rekening hanya bila boleh_rekap_transfer(). Tanpa p_batch, keadaan: siap / menunggu_lunas / tanpa_rekening / menunggu_gm (diajukan lewat cutoff, bukan cepat menunggu) / cepat (disetujui jalur cepat, belum batch). Dengan p_batch: isi batch itu.
9. Trigger jaga_status_klaim_ehc() (ehck_jaga_status, BEFORE UPDATE ehc_klaim): perpindahan sah: diajukan → disetujui | ditolak | batal; disetujui → batal hanya bila batch null; ditolak & batal final.
   - gm_* & gm_jalur hanya berubah bersama perpindahan dari diajukan.
   - transfer_batch_id: null → isi hanya bila NEW.status='disetujui' dan rhj.batch='on'; isi → null hanya bila rhj.batch='on' dan OLD.ditransfer_pada null; isi → isi lain ditolak.
   - ditransfer_pada: hanya null → isi, dengan batch terisi dan rhj.batch='on'.
   - OLD.status ≠ diajukan → beku: so_id, pic_id, bank, no_rekening, atas_nama, cara_bayar, keperluan, customer_id, periode, tanggal, lintas_customer, keterangan, dibuat_*. sales_rep_id tetap bebas (gabungkan_sales / batalkan_ubah_sales).
10. Trigger jaga_anak_klaim_ehc() — ekal_jaga dan ekb_jaga, BEFORE INSERT OR UPDATE pada alokasi/berkas: induk ≠ diajukan atau ber-batch → 42501.
11. Trigger tandai_ehc_ditransfer() — tb_tandai_ditransfer, AFTER UPDATE OF no_referensi ON transfer_batch WHEN (old null, new terisi, jenis 'ehc'): simpan nilai rhj.batch → on → ehc_klaim.ditransfer_pada = now() untuk klaim batch itu → kembalikan nilai GUC.
12. ekt_tetap / ekp_tetap: raise 42501 'Riwayat tidak bisa diubah'.

B2. DIGANTI
13. putuskan_klaim_cepat (signature tetap): + FOR UPDATE, pemutus_terlibat → 42501, status harus diajukan.
    - Setuju: siapkan_setuju('cepat') TANPA syarat lunas, lintas boleh. Satu UPDATE di bawah rhj.cepat: cepat_ok=true + cepat_diputus_* + status 'disetujui' + gm_* + gm_jalur 'cepat'. Lalu putusan (cepat, setuju).
    - Tolak (default P2): seperti sekarang — cepat_ok=false, status tetap diajukan, ikut pemeriksaan sesudah tgl 18. Hanya ehc_cepat_log.
14. minta_klaim_cepat: blok klaim_ehc_lintas dibuang; reimburse diperiksa ke sales_rep_rekening (bukan header); pesan khusus untuk status disetujui.
15. batalkan_klaim_ehc: syarat cepat → `cepat_minta and cepat_ok is null` (cepat disetujui-belum-dibayar bisa dibatal GM/owner, ATURAN L71); klaim di batch → 'keluarkan dulu dari batch'.
16. ehc_klaim_siap_transfer(p_bulan) (ACL tetap): status='disetujui'; batch null; periode ≤ p_bulan; cara transfer/reimburse/tunai; ada ehc_klaim_tujuan; NOT (cepat_minta AND cepat_ok IS DISTINCT FROM false); tidak terkunci pengajuan; alokasi>0; ≥1 berkas aktif; semua SP lunas & tidak batal. Syarat lintas DIBUANG.
17. rekap_ehc_cepat() (jsonb sama), tanpa DELETE: advisory lock; kandidat (disetujui & cepat_ok & batch null & ada tujuan) FOR UPDATE; SP FOR SHARE, SP batal dilewati; hitung dulu, n=0 → tanpa INSERT; INSERT batch (bulan/tanggal WIB, cepat, jumlah/total langsung) → rhj.batch on → set batch → GET DIAGNOSTICS. Lunas tidak disyaratkan.
18. ajukan_transfer: hanya blok `if p_jenis='ehc' and hari_ini_wib() <= cutoff_ehc…` diganti `if p_jenis='ehc' then raise '…EHC tidak lewat pengajuan: GM memeriksa per klaim sesudah tgl 18, finance mengunci daftar mulai tgl 20' using errcode='0A000'`. Cabang komisi byte-identik (dibuktikan diff).
19. jaga_batch: tambah beku dibuat_oleh, dibuat_pada, periode_bayar; ref_oleh/ref_pada dipaksa = OLD kecuali no_referensi berubah (diisi otomatis); no_referensi yang sudah terisi tidak boleh dikosongkan; jalan rhj.batch tetap (komisi).
20. jaga_nilai_terkunci: cabang ehc tambah status ≠ diajukan & (nominal atau kas) berubah → 42501. Cabang komisi identik.
21. periksa_saldo_ehc_sp: v_belum = Σ alokasi FILTER (k.ditransfer_pada IS NULL).
22. VIEW antrean_gm — dari pg_get_viewdef DEV saat diterapkan; kolom & security_invoker tetap.
    - Buang cabang 'ehc_dini'.
    - 'ehc_cepat': ref_id tetap k.id; tanggal (cepat_diminta_pada at time zone 'Asia/Jakarta')::date; pihak customer penerima (+' (LINTAS)'); keterangan + keperluan/cara + LINTAS / SP belum lunas.
    - BARU 'ehc_periksa': ref_id = −k.id (tameng tab lama); nomor 'EHC #id · no_sp'; pihak customer penerima (+LINTAS); tanggal cutoff_ehc(periode)+1; keterangan 'Periksa EHC periode X — Rp… · keperluan/cara' + penanda LINTAS / SP belum lunas / TANPA LAMPIRAN / cepat ditolak; WHERE diajukan, batch null, hari_ini_wib() > cutoff, bukan cepat menunggu.
    - Cabang lain byte-identik.
23. VIEW ehc_cepat_siap: WHERE status='disetujui' AND cepat_minta AND cepat_ok AND batch null; bank/no_rekening/atas_nama dari ehc_klaim_tujuan; kolom lama tetap urut, tambahan di belakang: customer_id, customer, keperluan, lintas_customer, rekening_ada, ada_sp_batal.

B3. TIDAK DISENTUH
- simpan_klaim_ehc, putuskan_transfer, isi_referensi_batch, batalkan_klaim_cepat, klaim_(ehc_)terkunci_pengajuan, ajukan_klaim_komisi, laporan_komisi, ehc_saldo_sp, kas_sales.
- tarik_pengajuan_transfer, rekap_transfer (berisi DELETE; cabang ehc mati: tak ada pengajuan EHC hidup dan mesin status menolak batch tanpa rhj.batch).
- RLS ehc_klaim / ehc_cepat_log (menunggu P4).

C. ALUR PER PERAN
SALES: setor kapan saja (lampiran wajib, multi-SP, lintas ditandai; periode = periode_ehc(hari WIB)). Sampai tgl 18 ubah/batal (#61); "Minta EHC cepat" kapan saja, kini juga untuk lintas. Sesudah 18 terkunci; pil: menunggu GM → disetujui · menunggu SP lunas / dibayar mulai 20 <bulan> → masuk daftar bayar #n → ditransfer; atau ditolak + alasan (saldo kembali; bila komisi SP sudah diklaim, sisa ke kas — P3). Ditolak final; ajukan ulang = klaim baru.
GM/OWNER (mulai tgl 19): tile "EHC perlu diperiksa GM" (per klaim) atau halaman EHC "Perlu diperiksa GM" (centang). Laci menampilkan isi klaim, tujuan terkini, LINTAS, tiap SP (lunas, saldo, tertutup), lampiran, riwayat. Setujui/Tolak (tolak wajib alasan); ditolak sistem bila belum cutoff, versi basi, tanpa lampiran, SP batal, saldo kurang, reimburse tanpa rekening sales, pemutus terlibat (P1). Massal hanya non-lintas; tolak selalu satu per satu. Yang belum diputus tidak menghalangi klaim lain dan ikut tgl 20 berikutnya. Disetujui-belum-dibayar hanya dibatal GM/owner + alasan (bila di batch: finance keluarkan dulu). EHC cepat diputus di laci yang sama kapan saja.
FINANCE (mulai tgl 20; owner/GM juga boleh): blok "EHC periode X": Siap dibayar (rekening, nominal, total per sales), Menunggu SP lunas (umur), Menunggu GM (peringatan), Cepat. Langkah: (1) Kunci daftar (sekali per periode, tidak sebelum tgl 20 WIB) → (2) transfer di bank sesuai batch → (3) yang gagal: Keluarkan + alasan → (4) isi referensi → ditransfer_pada terisi, batch beku. EHC emergency: rekap_ehc_cepat kapan saja, langkah 2–4 sama. Lenni melihat blok tanpa tombol dan tanpa rekening.
KOMISI tidak berubah: ajukan_transfer('komisi') → putuskan_transfer → rekap_transfer('komisi') → referensi; EHC tgl 20 terpisah dari komisi tgl 25.

D. LAYAR (index.html)
D1 PRASYARAT, dirilis LEBIH DULU dari 141: formGmPutus ELSE (14192–14199) hanya untuk harga/telat (PATCH /sales_orders); jenis lain → tampilPesan("Jenis antrean '…' belum dikenal layar ini — muat ulang halaman.") tanpa request. Buang cabang ehc_dini (14190), GM_JENIS_HPP 'ehc_dini' (13974), GM_LABEL.ehc_dini (13693), tile (13752).
D2 Tab GM: GM_LABEL.ehc_periksa "EHC perlu diperiksa GM" + tile (>0) bertautan ke halaman EHC 'periksa'. formGmPutus: ehc_periksa/ehc_cepat → formGmPutusEhc(jenis, Math.abs(ref)) memuat ehc_klaim (EHC_KOLOM), ehc_saldo_sp, putusan/log/cepat_log, sales_rep_rekening (reimburse), rpc klaim_ehc_pemutus_terlibat. Setujui mati beralasan bila terlibat / tanpa lampiran / SP batal / reimburse tanpa rekening / belum cutoff; Tolak wajib gm_catatan; p_versi = k.diubah_pada || k.dibuat_pada (string apa adanya); ehc_periksa → /rpc/putuskan_klaim_ehc, ehc_cepat → /rpc/putuskan_klaim_cepat; 40001 → muat ulang laci. Cabang 'transfer' (komisi) tetap.
D3 Tab EHC: EHC_KOLOM + diubah_pada, dibuat_oleh, gm_pada, gm_catatan, gm_jalur, ditransfer_pada, cepat_diputus_pada, alokasi sales_orders(no_sp,lunas,customer_id). EHC_HAL + LANJUT.ehc.hlm (7876): saldo · diajukan "Diajukan / menunggu GM" · periksa (hanya bolehApprove; status=diajukan & batch null & periode=lt.<periodeEhcDari(hariIniJkt())> & or=(cepat_minta.is.false,cepat_ok.is.false)) · disetujui "Disetujui · belum dibayar" · selesai "Daftar bayar / ditransfer" · batal. Halaman periksa: centang (lintas/terlibat tak bisa), ringkasan baris (nominal, SP+lunas, lampiran), "Setujui yang dicentang (n · Rp…)" → setujui_klaim_ehc_massal, hasil per klaim; "Periksa" → laci GM. pilStatusEhc/barisKlaimEhc: status sesuai C + ketGm. tombolCepat/bolehMintaCepat: pengecualian lintas dibuang. Teks KET/kosongAsli (11785–11818) & formEhc (12029–12042) diperbarui.
D4 Laporan Finance: helper bolehRekapTransfer() (owner/gm/finance) menyembunyikan tombol uang dari Lenni. bulanTransfer('ehc') = periodeBayarEhc(hariIniJkt()); komisi tetap. forEach (13449) cabang ehc → blokBayarEhc(): /rpc/ehc_daftar_bayar (4 kelompok, dapat diurutkan); tombol "Kunci daftar bayar EHC periode X" → /rpc/rekap_ehc_bulanan; bila batch ada: rincian (p_batch) + per baris "Keluarkan (transfer gagal)" → /rpc/keluarkan_klaim_ehc_batch, lalu isiReferensi lama. "Tiga langkah…" hanya komisi. muatBatch + periode_bayar, pil bulanan/cepat/pengajuan, "BELUM ADA REFERENSI" merah, "Rincian" batch EHC (cepat juga). EHC emergency + kolom customer/LINTAS/keperluan/rekening_ada/ada_sp_batal. Blok komisi tidak diubah.
D5 GALAT_BERKAS: /putuskan_klaim_ehc|setujui_klaim_ehc_massal|rekap_ehc_bulanan|keluarkan_klaim_ehc_batch|ehc_daftar_bayar|ehc_klaim_putusan|ehc_klaim_tujuan|periode_bayar|gm_jalur|ditransfer_pada|pemutus_terlibat/ → 141/142/143; SIAP_DB.ehc ditambah; saat merge 50–61 laporan & kas masuk MUAT_DIAM.

E. MIGRASI DATA & RILIS
Berkas (<80 KB, di-grep kata terlarang, tanpa berkas manual): db/141-ehc-periksa-gm-struktur.sql (pra-cek, DDL, tabel, backfill, CHECK, indeks, trigger) · db/142-ehc-periksa-gm-fungsi.sql (RPC, pengganti, grant) · db/143-ehc-periksa-gm-view.sql (antrean_gm, ehc_cepat_siap).
Pra-cek DO-blok gagal tertutup: raise bila ada transfer_pengajuan 'ehc' menunggu/disetujui ("Tuntaskan dulu lewat alur lama"); notice jumlah ehc_dini_minta terbuka.
Backfill sebelum CHECK & trigger:
(a) 'disetujui' hasil 140 dan (b) 'diajukan' ber-batch → 'disetujui', gm_jalur 'konversi', gm_pada = coalesce(batch.dibuat_pada, k.dibuat_pada), gm_catatan 'Konversi 141: dibayar lewat alur lama (batch #n)', ditransfer_pada = coalesce(ref_pada, dibuat_pada) batch, tujuan dari header, putusan (konversi, setuju).
(c) diajukan + cepat_ok + belum batch → 'disetujui', gm_jalur 'cepat', gm_oleh/gm_pada dari cepat_diputus_*, tujuan dari header (reimburse kosong → sales_rep_rekening saat ini), putusan (konversi).
(d) klaim diajukan lain tidak diubah; yang lewat cutoff langsung masuk antrean (di PROD termasuk lintas & reimburse tersangkut).
DEV: (a)–(c) 0 baris; #6/#7 tetap diajukan, mulai 19 Okt di antrean, hanya bisa ditolak (tanpa lampiran) atau dibatalkan sebelumnya.
Sidik sebelum = sesudah: md5 so_ringkas, ehc_saldo_sp per SP, kas_sales, komisi_klaim+nilai #12/#13, laporan_komisi('2026-01-01','2026-12-31'), baris antrean_gm non-EHC.
PROD (Hannes): (1) DENGAN LAYAR LAMA yang masih jalan di PROD, tuntaskan semua transfer_pengajuan jenis 'ehc' berstatus menunggu/disetujui. Caranya: GM memutus di antrean 'transfer', lalu finance menekan 'Tandai EHC … sudah ditransfer' (rekap_transfer) atau 'Tarik pengajuan'. Minta finance tidak mengajukan EHC baru. (2) Dalam satu sesi, jalankan migrasi tertunda berurutan (termasuk 140, 140b), lalu 141 → 142 → 143. Bila pra-cek 141 berhenti, layar lama masih aktif: tuntaskan di situ, lalu ulangi 141. (3) SEGERA unggah index.html baru (D1 + layar tahap 3) dan minta semua tab dimuat ulang. (4) Uji asap per peran.
Layar baru TIDAK toleran sebelum 140/141. Halaman klaim EHC, laci GM EHC (termasuk EHC cepat) dan daftar bayar hanya menampilkan galat yang menunjuk berkas 141/142. Tombol pengajuan EHC lama (tarik/tandai ditransfer) sudah tidak ada di layar baru. Sebaliknya, layar lama gagal di halaman klaim EHC sesudah 141 (hak baca per kolom). Jadi jeda antara 141 dan unggah index.html harus sesingkat mungkin.

F. URUTAN PENGERJAAN
(1) Hannes menjawab P1–P4, dicatat di ATURAN B dulu (A2) → (2) FE D1 + commit → (3) 141/142/143 dari def DEV terbaru, terapkan di DEV, sidik → (4) uji rollback per peran → (5) FE D2–D5 + Playwright → (6) ATURAN B L69/L71/L72/L73 (+ GM per klaim, tgl 20 keras & sekali per periode, rekening dikunci saat setuju, keluarkan dari batch, larangan memutus sendiri) + HANDOFF + ALUR-KERJA (skill) dalam commit yang sama; push branch claude/….


## Skenario uji rollback (usulan penyusun)
- CARA: semua di DEV eesdtbcualkdawhykchj dalam SATU panggilan BEGIN … ROLLBACK, teks tanpa kata delete/drop. Peran: set local role authenticated + set_config('request.jwt.claims','{"sub":"<uuid>","role":"authenticated"}',true). GM bf3f3b71, owner Hannes b8213cb9 (rep 13), owner Felix ffae9b24, sales Alfred (rep 2, punya rekening) + 1 sales lain. Finance/staff/Lenni/Ichi disimulasikan dengan UPDATE profiles.peran milik akun vonny/nonaktif sebagai postgres di dalam transaksi. 'Sesudah cutoff' = UPDATE ehc_klaim SET periode='2026-09' (postgres, klaim masih diajukan). Lampiran = INSERT ehc_klaim_berkas sebagai postgres. Hari ini 9 Okt, jadi periode_bayar_ehc = '2026-09'. Sesudah rollback, cek ulang bahwa hari_ini_wib() dan data #6/#7 tidak berubah.
- S1 [sales Alfred] putuskan_klaim_ehc, setujui_klaim_ehc_massal, putuskan_klaim_cepat, rekap_ehc_bulanan, keluarkan_klaim_ehc_batch, ehc_daftar_bayar → semuanya 42501.
- S2 [sales] UPDATE ehc_klaim status/gm_* lewat role authenticated → 0 baris (tanpa policy UPDATE). INSERT ehc_klaim_putusan / ehc_klaim_tujuan dan UPDATE ehc_klaim_nilai → ditolak RLS.
- S3 [sales pemilik] simpan_klaim_ehc pada klaim periode 2026-10 → OK (#61 tetap). Sesudah periode di-set 2026-09 → 22023 'terkunci'. Sesudah klaim disetujui/ditolak → 22023 status.
- S4 [sales pemilik] membaca gm_catatan, ehc_klaim_putusan, dan ehc_klaim_tujuan klaimnya sendiri. [sales lain] → 0 baris.
- S5 [sales] minta_klaim_cepat pada klaim lintas berlampiran → OK. Pada klaim disetujui → 22023. Reimburse milik rep tanpa sales_rep_rekening → 22023 'rekening sales belum diisi'.
- G1 [GM] putuskan_klaim_ehc atas #6 periode 2026-10 pada 9 Okt → 22023 'diperiksa sesudah tgl 18'.
- G2 [GM] periode 2026-09, berkas ada, p_versi = string coalesce(diubah_pada,dibuat_pada) apa adanya, setuju → status disetujui, gm_oleh/gm_pada/gm_jalur 'periksa' terisi, 1 baris ehc_klaim_putusan (snapshot berisi alokasi + lunas) dan 1 baris ehc_klaim_tujuan (sumber pic). ehc_saldo_sp.terpakai SP41 tidak berubah. Baris 'ehc_periksa' hilang dari antrean_gm.
- G3 [GM] p_versi null → 40001. Klaim di-UPDATE diubah_pada sesudah versi dibaca → 40001. Versi baru → OK.
- G4 [GM] tolak tanpa catatan → 22023. Dengan catatan → status ditolak; ehc_saldo_sp.sisa SP naik sebesar alokasi; laporan_komisi.ehc_diklaim turun. Sesudah itu simpan_klaim_ehc, batalkan_klaim_ehc, minta_klaim_cepat, dan putuskan_klaim_ehc kedua → 22023.
- G5 Klaim uji atas SP158 (komisi #12 sudah diklaim, sisipkan sebagai postgres) ditolak GM → kas_sales rep-nya naik sebesar alokasi (sesuai P3 default).
- G6 #7 tanpa lampiran (periode di-set 2026-09): setuju → 22023 'tanpa lampiran'; tolak dengan alasan → OK.
- G7 Reimburse milik rep tanpa rekening: setuju → 22023. Sesudah simpan_rekening_sales oleh finance simulasi → setuju OK; ehc_klaim_tujuan sumber 'sales' berisi rekening itu; header ehc_klaim tidak berubah.
- G8 Klaim transfer yang PIC-nya dinonaktifkan sesudah disetor → setuju 22023. Rekening PIC disamakan dengan rekening sales → 42501.
- G9 Empat mata (default P1): klaim dengan dibuat_oleh = GM → GM 42501, Felix OK. Klaim rep 13 → Hannes 42501, GM OK. Klaim yang pernah diubah GM (log 'ubah' oleh GM) → GM 42501. rpc klaim_ehc_pemutus_terlibat mengembalikan nilai yang sama.
- G10 Massal 5 butir campur → klaim lintas 'dilewati'; klaim ditolak 'gagal' + pesan; versi basi 'gagal' 40001; sisanya disetujui, masing-masing dengan baris putusan sendiri; butir yang gagal tidak membatalkan yang lain. Isi >100 butir atau duplikat → 22023.
- G11 batalkan_klaim_ehc: GM atas klaim disetujui belum batch (termasuk cepat disetujui) → batal, saldo kembali. Sales atas klaim disetujui → 22023. Siapa pun atas klaim ditolak → 22023. Klaim di batch → 22023 'keluarkan dulu'.
- G12 [GM] UPDATE sales_orders SET batal=true + SET CONSTRAINTS ALL IMMEDIATE pada SP dengan: klaim disetujui belum dibayar / cepat disetujui belum batch / klaim di batch tanpa referensi → 23514. Sesudah referensi batch diisi → pemeriksaan EHC lolos.
- C1 [sales] minta cepat untuk klaim lintas dengan SP belum lunas → [GM] putuskan_klaim_cepat setuju → cepat_ok true, status disetujui, gm_jalur 'cepat', ehc_klaim_tujuan terisi. Klaim muncul di ehc_cepat_siap, TIDAK di ehc_klaim_siap_transfer maupun 'ehc_periksa'.
- C2 Tolak cepat tanpa alasan → 22023. Dengan alasan → cepat_ok false, status tetap diajukan. Periode 2026-09 → muncul di 'ehc_periksa' dengan penanda 'cepat ditolak' (default P2).
- C3 [finance] rekap_ehc_cepat → batch cepat=true, bulan '2026-10', tanggal = hari_ini_wib(). Klaim dengan SP belum lunas tetap ikut; klaim batal atau SP batal tidak ikut. Panggilan kedua → batch null dan count(transfer_batch) tetap (tidak ada baris kosong).
- C4 GM yang meminta cepat lalu memutusnya sendiri → 42501.
- F1 [finance] putuskan_klaim_ehc dan putuskan_klaim_cepat → 42501.
- F2 [finance] rekap_ehc_bulanan('2026-10') pada 9 Okt → 22023 (gerbang tgl 20). rekap_ehc_bulanan('2026-09') → batch jenis ehc, bulan = periode_bayar = '2026-09', cepat false, tanggal = hari_ini_wib(). Isi HANYA klaim disetujui yang SP-nya lunas dan berlampiran; jumlah/total = Σ ehc_klaim_nilai; menunggu_lunas & menunggu_gm benar.
- F3 Lunas SP alokasi dicabut oleh GM dalam transaksi → klaim tidak ikut dan terhitung menunggu_lunas. Klaim lintas yang disetujui ikut batch. Klaim diajukan dan ditolak tidak ikut.
- F4 Panggilan kedua untuk periode yang sama → 22023 'sudah dikunci'. Daftar kosong → jsonb tanpa INSERT (count batch tetap).
- F5 keluarkan_klaim_ehc_batch tanpa alasan → 22023. Dengan alasan → klaim keluar dari batch, jumlah/total batch turun, ada baris putusan 'keluar_batch', klaim tetap disetujui. Semua isi dikeluarkan → rekap_ehc_bulanan periode yang sama boleh lagi. Sales → 42501.
- F6 isi_referensi_batch → ref_oleh/ref_pada otomatis dan ehc_klaim.ditransfer_pada terisi untuk semua klaim di batch. Sesudah itu: keluarkan → 22023; UPDATE no_referensi menjadi null, atau total/dibuat_oleh/ref_pada/periode_bayar langsung (role finance) → ditolak jaga_batch.
- F7 Sesudah batch: simpan_klaim_ehc dan batalkan_klaim_ehc → 22023; UPDATE ehc_klaim_nilai, INSERT/UPDATE ehc_klaim_alokasi dan ehc_klaim_berkas sebagai postgres → ditolak trigger.
- F8 ehc_daftar_bayar('2026-09'): finance melihat rekening; Lenni/staff (simulasi) melihat baris tanpa rekening; vonny dan sales → 42501. ehc_daftar_bayar(null, batch) mengembalikan isi batch.
- F9 ajukan_transfer('ehc', '2026-09') → 0A000.
- K1 Regresi komisi [GM/finance]: ajukan_transfer('komisi','2026-10') → pengajuan menunggu berisi #12/#13, total = Σ komisi_klaim_nilai, jsonb sama dengan baseline sebelum 141. antrean_gm memuat baris 'transfer'. putuskan_transfer tolak tanpa alasan → 22023; setuju → rekap_transfer('komisi') → batch komisi (periode_bayar null) → isi_referensi_batch → ref_* otomatis, tidak ada ehc_klaim yang berubah. tarik_pengajuan_transfer pada 'menunggu' tetap berfungsi.
- K2 Diff teks ajukan_transfer lama vs baru hanya di blok ehc. Cabang komisi jaga_nilai_terkunci identik; nominal komisi beku sesudah masuk pengajuan hidup.
- A1 antrean_gm: 'ehc_periksa' hanya untuk klaim diajukan yang lewat cutoff dan bukan cepat menunggu, ref_id negatif, hilang sesudah diputus. Tidak ada baris 'ehc_dini'. Tanggal 'ehc_cepat' dalam WIB. Sales hanya melihat barisnya sendiri. md5 baris jenis non-EHC sebelum = sesudah 143.
- V1 [vonny simulasi] ehc_klaim_putusan, ehc_klaim_tujuan, ehc_klaim_nilai → 0 baris. Bila P4 = dipersempit: ehc_klaim dan ehc_cepat_log juga 0 baris. Lenni/staff tetap membaca klaim & nilai, tetapi ehc_klaim_tujuan 0 baris.
- I1 Sebagai postgres: UPDATE status ditolak→disetujui, batal→diajukan, disetujui→ditolak → ditolak trigger. Mengisi transfer_batch_id tanpa rhj.batch atau pada klaim diajukan → ditolak. Mengubah gm_catatan sesudah diputus → ditolak. UPDATE ehc_klaim_putusan / ehc_klaim_tujuan → ditolak.
- I2 Perubahan sales_rep_id (pola gabungkan_sales) pada klaim disetujui/ber-batch → lolos trigger.
- I3 has_function_privilege('anon', …) = false untuk semua RPC baru. siapkan_setuju_klaim_ehc, putuskan_klaim_ehc_inti, dan ehc_klaim_siap_transfer tidak bisa dieksekusi authenticated.
- I4 Sidik md5 so_ringkas, ehc_saldo_sp, kas_sales, komisi #12/#13, laporan_komisi, dan antrean non-EHC sebelum = sesudah 141–143. grep berkas 141–143 tanpa kata terlarang.
- P1 Playwright tab GM: baris 'ehc_periksa' membuka laci EHC, bukan PATCH sales_orders. Jenis antrean palsu → pesan, tanpa request. Simulasi index.html lama pada baris 'ehc_periksa' → PATCH ke id negatif, tidak ada SP yang berubah.
- P2 Laci EHC: Setujui mati dengan alasan untuk klaim tanpa lampiran / pemutus terlibat. Payload p_versi = string apa adanya. Galat 40001 → laci dimuat ulang. Tolak tanpa alasan tidak mengirim request.
- P3 Halaman EHC 'periksa': baris lintas/terlibat tidak bisa dicentang; hasil massal tampil per klaim; pil status sesuai keadaan (menunggu GM, menunggu SP lunas, dibayar mulai 20, masuk daftar bayar, ditransfer, ditolak + catatan); tombol cepat muncul untuk klaim lintas.
- P4 Laporan Finance: blok EHC periode 2026-09 pada 9 Okt; urutan kunci → rincian → keluarkan → referensi berjalan. Lenni melihat tanpa tombol dan tanpa rekening. Blok komisi tidak berubah (snapshot DOM sama).

## Objek bersama (koordinasi sesi lain / komisi)
- VIEW antrean_gm — juga dirawat sesi 120–139 (cabang harga/telat/harga_khusus/ubah/kirim/tanpa_po/transfer). Wajib dibangun dari pg_get_viewdef DEV saat diterapkan; md5 cabang non-EHC sebelum = sesudah.
- transfer_batch + trigger tb_jaga/jaga_batch + zz_audit_transfer_batch + isi_referensi_batch — dipakai batch komisi (rekap_transfer). Pengerasan jaga_batch dan trigger baru tb_tandai_ditransfer (hanya jenis 'ehc') harus tetap membiarkan jalur rhj.batch komisi.
- ajukan_transfer, putuskan_transfer, rekap_transfer, tarik_pengajuan_transfer, transfer_pengajuan(+_baris), tpj_hidup_uniq — jalur komisi tgl 25. Hanya blok 'ehc' di ajukan_transfer yang diganti; sisanya byte-identik.
- jaga_nilai_terkunci — dipakai ehc_klaim_nilai (ekn_kunci_batch) dan komisi_klaim_nilai (kkn_kunci_batch). Cabang komisi dan klaim_terkunci_pengajuan('komisi', …) tidak berubah.
- laporan_komisi, ehc_saldo_sp, kas_sales, komisi_klaim — semantik 'tertutup saat komisi diklaim' dan penyaring status diajukan/disetujui. Tidak diubah; ehc_ditransfer di laporan_komisi masih berbasis transfer_batch_id.
- sales_orders (lunas/batal) + trigger so_jaga_saldo_ehc / sol_jaga_saldo_ehc / so_jaga_hapus_ehc → periksa_saldo_ehc_sp (definisi 'belum dibayar' berubah ke ditransfer_pada). Pelunasan (Ichi/GM/owner) menentukan klaim 'siap'.
- gabungkan_sales / batalkan_ubah_sales — memindah sales_rep_id di ehc_klaim; trigger mesin status wajib membiarkan kolom ini.
- customer_pics (aktif, rekening, terkunci) dan sales_rep_rekening + simpan_rekening_sales — dibaca ulang saat GM setuju untuk mengunci ehc_klaim_tujuan.
- Fungsi peran bersama: boleh_approve, boleh_rekap_transfer, boleh_lihat_nilai_klaim, boleh_lihat_semua_jual, boleh_minta_klaim_cepat, peran_saya, sales_rep_saya, klaim_ehc_saya, hari_ini_wib, cutoff_ehc, periode_ehc.
- gm_konteks_keputusan (masih punya cabang ehc_dini, dibiarkan) dan view sales_beban (membaca ehc_klaim; ikut berubah untuk Vonny/Lie Sian/Ichi bila P4 = dipersempit).
- index.html bersama: formGmPutus (ELSE dan cabang transfer/ehc_cepat), GM_LABEL, GM_JENIS_HPP, tile panelGmAntre, Laporan Finance gambarLaporan (forEach ['ehc','komisi'], muatBatch, muatPengajuan, isiReferensi, blok komisi), GALAT_BERKAS, SIAP_DB, LANJUT.ehc/gm, serta pola MUAT_DIAM / var awal dari branch 50–61 (rawan bentrok saat merge).
- ATURAN.md bagian B (EHC L68–L74; ATURAN branch 50–61 masih memuat 'EHC tidak memerlukan lampiran'), HANDOFF.md 'Sesi EHC & komisi', claude/ALUR-KERJA-ERP.md (lewat skill alur-kerja).

## Catatan risiko
1. Urutan rilis FE↔DB. index.html lama menjatuhkan jenis antrean yang tidak dikenal ke ELSE formGmPutus, yang menjalankan PATCH /sales_orders?id=eq.<ref> {harga_ok}.
   - Tameng: ref_id 'ehc_periksa' dibuat negatif, sehingga tab lama menulis ke id yang tidak ada; ELSE dikeraskan; FE dirilis dulu dan semua tab dimuat ulang.
   - 'ehc_cepat' tetap positif karena FE lama sudah punya cabangnya.

2. antrean_gm dipakai bersama sesi 120–139. CREATE OR REPLACE dari salinan lama akan menghapus cabang mereka. Bangun dari pg_get_viewdef saat menerapkan, lalu buktikan dengan md5 baris non-EHC.

3. Batas MCP.
   - Kata delete/drop, termasuk 'on delete' dan 'dropdown', serta berkas >80 KB membuat alat macet.
   - Karena itu: FK tanpa klausa hapus, rekap_ehc_cepat ditulis ulang tanpa DELETE, rekap_transfer/tarik_pengajuan_transfer tidak disentuh, berkas dipecah 141/142/143, grep sebelum kirim.

4. Perubahan perilaku di PROD.
   - Klaim 'diajukan' tidak lagi pernah dibayar tanpa putusan GM.
   - Pada hari rilis, klaim lama yang sudah lewat cutoff membanjiri antrean GM. Klaim lama tanpa lampiran hanya bisa ditolak (saldo kembali, bisa menjadi kas sales).
   - Pengajuan EHC lama wajib dituntaskan dulu; pra-cek gagal tertutup.
   - GM dan finance perlu diberi tahu.

5. Gerbang tgl 20 keras dan satu batch per periode.
   - Bila tgl 20 libur, pembayaran tidak bisa dimajukan (jalan darurat: EHC cepat).
   - Klaim yang disetujui atau lunas sesudah batch dikunci menunggu sebulan.
   - Finance yang terlambat tidak menghilangkan klaim, karena periode lama ikut otomatis.

6. Rekening dikunci saat GM setuju. Koreksi rekening sales sesudahnya tidak ikut ke klaim; jalan keluarnya GM membatalkan lalu sales menyetor ulang (mundur satu periode). Sisi baiknya, finance tidak bisa mengalihkan tujuan sesudah GM melihatnya. Tahap berikut bisa menambah 'segarkan tujuan' khusus GM.

7. Jendela antara kunci dan referensi: klaim sudah ber-batch tetapi uang belum keluar.
   - Layar EHC dan periksa_saldo_ehc_sp memakai ditransfer_pada.
   - laporan_komisi.ehc_ditransfer (bersama komisi, tidak disentuh) sudah menghitungnya. Selaraskan di tahap 4.
   - Finance wajib mengisi referensi; batch tanpa referensi ditandai merah.

8. Pencabutan lunas sesudah EHC dibayar tidak dicegah, hanya tercatat di audit. FOR SHARE hanya melindungi selama transaksi kunci. Usul tahap 4: trigger yang menolak atau mencatat pencabutan lunas.

9. Larangan memutus sendiri (P1) bisa macet bila hanya satu pemutus aktif (contoh: Felix nonaktif → klaim rep 13 hanya bisa diputus GM).

10. Persetujuan massal bisa menjadi stempel. Peredam: lintas dan klaim milik sendiri dikecualikan, batas 100, versi per baris, ringkasan per baris di layar, tolak selalu satu per satu.

11. Kepala ehc_klaim (gm_catatan, alasan cepat, salinan rekening reimburse dari simpan_klaim_ehc) tetap terbaca Vonny/Lie Sian/Ichi sampai P4 diputus. Rekening tujuan baru disimpan terpisah (ehc_klaim_tujuan, RLS setara srr_baca), jadi kebocoran tidak bertambah.

12. rekap_transfer cabang 'ehc' (berisi DELETE, tidak diganti) tetap ada tetapi mati. Bila dipanggil, ia ditolak dengan pesan 'belum ada persetujuan GM' (menyesatkan) atau oleh mesin status. FE tidak lagi memanggilnya.

13. Sisa UTC untuk komisi: transfer_batch.tanggal default CURRENT_DATE (rekap_transfer) dan ajukan_klaim_komisi current_date. Dibereskan tahap 4.

14. Klaim yang disetujui tetapi SP-nya tidak pernah lunas akan menggantung dan terus memakan saldo SP. Dipantau lewat kelompok 'Menunggu SP lunas' beserta umurnya; GM membatalkan bila perlu.

15. Pemisahan tugas pembayaran tidak dipaksa: GM boleh menyetujui dan juga mengunci batch. Keduanya tercatat (gm_oleh vs transfer_batch.dibuat_oleh + audit).

16. Uji: DEV tidak punya akun finance/staff/Lenni, jadi semuanya disimulasikan dalam transaksi. p_versi rapuh bila FE mengolahnya lewat Date JS; diuji khusus (P2).

17. Dua log untuk jalur cepat (ehc_cepat_log dan ehc_klaim_putusan), jadi laci GM membaca keduanya. Sumber kebenaran putusan adalah ehc_klaim_putusan dan gm_*.
