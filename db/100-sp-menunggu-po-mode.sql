-- Berkas 100 (#10): antrean "SP menunggu PO" tahu MODE PO tiap SP, supaya SP yang modenya belum
--   dinyatakan (gagal ditandai "tanpa PO" saat disimpan) kelihatan dan bisa dicoba lagi.
--
-- Keadaan DB saat dikerjakan: pintu resmi sudah ada (berkas 86/88) — jaga_kolom_sales bagian f
--   meloloskan tanpa_po_* selama flag rhj.tanpa_po = '1' yang hanya dinyalakan tandai_sp_tanpa_po()
--   / izinkan_invoice_tanpa_po(); tandai_sp_tanpa_po() mengizinkan PEMBUAT SP (sales: SP miliknya)
--   sebelum cek Vonny & sebelum barang keluar. Uji rollback: sales pembuat → berhasil; PATCH langsung
--   tanpa_po_alasan → tetap ditolak. Jadi fungsi tidak diubah — cukup view.
-- Perubahan: kolom aditif di UJUNG view sp_menunggu_po: po_menyusul, tanpa_po_alasan, dibuat_oleh,
--   vonny_ok, mode_po ('tanpa_po' | 'menyusul' | 'belum'). security_invoker WAJIB disebut ulang
--   (tanpa klausa WITH, CREATE OR REPLACE VIEW mengganti reloptions → RLS terlewati).
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 2026-09-29 lewat migrasi sp_menunggu_po_mode. Belum ke produksi.
-- Data: tidak ada yang diubah.

create or replace view public.sp_menunggu_po with (security_invoker = on) as
select s.id as so_id, s.no_sp, s.tanggal, s.kepada, s.customer_id, s.sales_rep_id,
       s.po_menyusul_alasan as alasan, s.po_menyusul_pada, current_date - s.tanggal as umur_hari,
       s.no_surat_jalan is not null as sudah_kirim, s.tgl_surat_jalan, s.tanpa_po_ok,
       coalesce(r.grand_total, 0::numeric) as grand_total,
       s.po_menyusul, s.tanpa_po_alasan, s.dibuat_oleh, s.vonny_ok,
       case when s.tanpa_po_ok then 'tanpa_po' when s.po_menyusul then 'menyusul'
            else 'belum' end as mode_po
  from public.sales_orders s left join public.so_ringkas r on r.so_id = s.id
 where s.po_id is null and not s.batal;

-- Periksa: select reloptions from pg_class where oid='public.sp_menunggu_po'::regclass;  → {security_invoker=on}

-- ROLLBACK (CREATE OR REPLACE tidak bisa membuang kolom → drop + create):
-- drop view public.sp_menunggu_po;
-- create view public.sp_menunggu_po with (security_invoker = on) as
-- select s.id as so_id, s.no_sp, s.tanggal, s.kepada, s.customer_id, s.sales_rep_id,
--        s.po_menyusul_alasan as alasan, s.po_menyusul_pada, current_date - s.tanggal as umur_hari,
--        s.no_surat_jalan is not null as sudah_kirim, s.tgl_surat_jalan, s.tanpa_po_ok,
--        coalesce(r.grand_total, 0::numeric) as grand_total
--   from public.sales_orders s left join public.so_ringkas r on r.so_id = s.id
--  where s.po_id is null and not s.batal;
