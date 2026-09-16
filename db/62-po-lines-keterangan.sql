-- Berkas 62 (#6): kolom keterangan per baris item PO.
-- Untuk baris 'barang' (catatan sales per item). Baris 'biaya' tetap pakai deskripsi (label ongkos).
-- Additive & aman (nullable). FE: input .po-ket per baris di poBarisHtml + listener di pasangBarisPo
--   + ikut disimpan lewat siapkanBarisPo -> POST /po_lines (keterangan).
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

ALTER TABLE public.po_lines ADD COLUMN IF NOT EXISTS keterangan text;
