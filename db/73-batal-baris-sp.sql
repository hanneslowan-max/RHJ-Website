-- Berkas 73 (#18): soft-cancel baris Surat Pesanan + relaksasi invarian SP=PO.
--
-- Kolom baru: sales_order_lines.batal (default false) + batal_alasan/_oleh/_pada. Data tak dihapus.
-- so_baris_hitung: TAMBAH filter "WHERE coalesce(l.batal,false)=false" (sisa definisi identik).
--   Efek berantai: baris batal lenyap dari so_ringkas (total_barang, total_ehc, sub_total, ppn,
--   grand_total, komisi, ada_bawah_list) → otomatis lenyap dari invoice, komisi, klaim EHC, laporan.
--   security_invoker=on WAJIB dipulihkan (create or replace view menghapusnya).
-- periksa_total_sp: dulu bandingkan so_ringkas.grand_total (kini aktif-saja) ke PO. Diubah: hitung
--   total SEMUA baris (termasuk batal) dengan rumus IDENTIK so_ringkas.grand_total, lalu banding ke PO.
--   Karena baris batal tak mengubah angkanya, total-semua-baris tetap = PO → invarian terjaga secara
--   struktur, nilai EFEKTIF SP menyesuaikan sisa item. SP tanpa pembatalan = perilaku 100% sama
--   (diverifikasi: 16/16 SP dev, total-semua-baris == so_ringkas.grand_total).
-- RPC: batalkan_baris_sp(p_line,p_alasan) & pulihkan_baris_sp(p_line).
--   - Izin: boleh_alur_jual() atau vonny; sales hanya SP miliknya (setara_owner/staff/vonny bebas).
--   - Hanya SEBELUM no_surat_jalan / no_invoice terbit (sesudah itu lewat proses retur, bukan di sini).
--   - Wajib beralasan; sisakan minimal 1 baris aktif (batalkan seluruh SP pakai batalkan_sp).
--   - set_config('rhj.usul','on') supaya trigger jaga_baris_sp_terkunci mengizinkan UPDATE langsung.
-- FE (index.html): SP_KOLOM embed +batal,batal_alasan,jenis; formDetailDoc SP dapat tombol
--   Batalkan/Pulihkan per baris + baris batal dicoret; ubahBatalBaris() memanggil RPC lalu muat ulang.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.
-- Badan lengkap view/fungsi/RPC = seperti diterapkan via apply_migration berkas73.

alter table public.sales_order_lines
  add column if not exists batal boolean not null default false,
  add column if not exists batal_alasan text,
  add column if not exists batal_oleh uuid,
  add column if not exists batal_pada timestamptz;

-- so_baris_hitung: + WHERE coalesce(l.batal,false)=false  |  so_ringkas tak berubah (baca view ini).
-- periksa_total_sp: hitung total semua baris (rumus so_ringkas) vs po_ringkas.grand_total.
-- batalkan_baris_sp / pulihkan_baris_sp: RPC soft-cancel (lihat riwayat migrasi Supabase untuk badan).
