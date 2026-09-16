-- Berkas 80: alihkan SEMUA kepemilikan sales Magdalena (id 14, nonaktif) → Menik (id 6, aktif).
-- Dampak dev (dicek sebelum jalan): 527 customers + 527 tautan_sales_baris.
--   0 leads/PO/SP/komisi_klaim/ehc_klaim/rekening atas nama Magdalena → tak ada riwayat uang tersentuh.
-- customers: sales_rep_id 14→6 + salesman_teks (teks lawas) → 'Menik' (konsisten, tak ter-revert re-import),
--   hanya baris milik 14 (tak merebut pelanggan sales lain).
-- tautan_sales_baris: sales_rep_id 14→6 (PK batch_id+customer_id → aman dari tabrakan).
-- Setiap perubahan customers tercatat audit_log (trigger customers_jejak) → dapat dilacak/dibalik.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

update public.customers   set sales_rep_id = 6, salesman_teks = 'Menik' where sales_rep_id = 14;
update public.tautan_sales_baris set sales_rep_id = 6 where sales_rep_id = 14;
