-- Berkas 85 (#1 UX): PO boleh menulis 1 baris "SET" (mis. "1 set roda hidup/mati @ 30"),
-- bukan langsung dipecah jadi baris pcs. Pemecahan ke komponen pcs terjadi saat SP dibuat
-- (stok & komisi tetap per pcs — Opsi B). Menyelaraskan PO dengan penawaran (yang sudah tampil set).
--
-- Kolom po_lines.set_id (FK product_sets). Baris SET: jenis='barang', product_id NULL, set_id terisi,
--   harga = harga set (= jumlah harga komponen), qty = jumlah set, deskripsi = nama set (jejak).
--   Nilai baris = qty*harga → po_ringkas TIDAK berubah (baris set = barang biasa bagi total/PPN).
-- Trigger jaga_jenis_baris (dipakai po_lines DAN sales_order_lines) dilonggarkan: baris 'barang'
--   tanpa product_id BOLEH bila punya set_id. Diakses via to_jsonb(new)->>'set_id' agar AMAN untuk
--   sales_order_lines yang tak punya kolom set_id (SP selalu per pcs; tak pernah baris set).
-- Diuji (transaksi rollback): INSERT po_line set (product_id NULL + set_id) LOLOS guard & po_ringkas
--   menghitung nilainya. SP=PO tetap terjaga: saat SP dibuat, FE memecah baris set ke komponen dengan
--   nett = harga komponen; jumlahnya = harga set × jumlah set = nilai baris set di PO.
--
-- FE (index.html): PO "+ Set" → tambah 1 baris set (qty=jumlah set bisa diubah, harga/set terkunci
--   dari definisi, tanpa diskon). PO_KOLOM embed set_id + product_sets(nama, komponen). formDetailDoc
--   PO tampilkan badge "set" + rincian. Saat buat SP dari PO, baris set dipecah ke komponen pcs
--   (pasangSp: reduce/expand). SP manual "+ Set" tetap langsung pcs (SP selalu per pcs).
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 16 Sep 2026. Belum ke produksi.
-- Badan lengkap fungsi = seperti diterapkan via apply_migration berkas85.

alter table public.po_lines add column if not exists set_id bigint references public.product_sets(id);

-- jaga_jenis_baris: + bypass baris SET (lihat migrasi untuk badan lengkap).
