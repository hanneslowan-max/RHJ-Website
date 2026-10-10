-- reloptions: (none)
create or replace view public.item_impor_untuk_sales as
 SELECT id,
    order_id,
    no_invoice,
    status_produksi,
    etd,
    eta,
    tanggal_tiba,
    kode,
    brand,
    kelompok,
    fungsi,
    diameter_mm,
    qty,
    satuan
   FROM ( SELECT l.id,
            l.order_id,
            o.no_invoice,
            o.status_produksi,
            o.etd,
            o.eta,
            o.tanggal_tiba,
            COALESCE(p.kode, '(tanpa kode)'::text) AS kode,
            p.brand,
            p.kelompok,
            p.fungsi,
            p.diameter_mm,
            l.qty,
            COALESCE(l.satuan, 'pcs'::text) AS satuan
           FROM import_lines l
             JOIN orders o ON o.id = l.order_id
             LEFT JOIN products p ON p.id = l.product_id) v
  WHERE akun_disetujui();
