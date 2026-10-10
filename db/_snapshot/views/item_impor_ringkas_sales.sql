-- reloptions: (none)
create or replace view public.item_impor_ringkas_sales as
 SELECT kode,
    brand,
    kelompok,
    fungsi,
    diameter_mm,
    qty_total,
    jumlah_kiriman,
    eta_terdekat,
    qty_sudah_tiba,
    qty_masih_jalan
   FROM ( SELECT COALESCE(p.kode, '(tanpa kode)'::text) AS kode,
            p.brand,
            p.kelompok,
            p.fungsi,
            p.diameter_mm,
            sum(l.qty) AS qty_total,
            count(DISTINCT l.order_id) AS jumlah_kiriman,
            min(o.eta) FILTER (WHERE o.status_produksi <> 'Sudah Diterima'::text) AS eta_terdekat,
            sum(l.qty) FILTER (WHERE o.status_produksi = 'Sudah Diterima'::text) AS qty_sudah_tiba,
            sum(l.qty) FILTER (WHERE o.status_produksi <> 'Sudah Diterima'::text) AS qty_masih_jalan
           FROM import_lines l
             JOIN orders o ON o.id = l.order_id
             LEFT JOIN products p ON p.id = l.product_id
          GROUP BY (COALESCE(p.kode, '(tanpa kode)'::text)), p.brand, p.kelompok, p.fungsi, p.diameter_mm) v
  WHERE akun_disetujui();
