-- reloptions: (none)
create or replace view public.pelanggan_per_sales as
 SELECT sales_rep_id,
    sales_nama,
    sales_jenis,
    jumlah_pelanggan,
    jumlah_hitam
   FROM ( SELECT r.id AS sales_rep_id,
            r.nama AS sales_nama,
            r.jenis AS sales_jenis,
            count(c.id) AS jumlah_pelanggan,
            count(c.id) FILTER (WHERE c.blacklist) AS jumlah_hitam
           FROM sales_reps r
             LEFT JOIN customers c ON c.sales_rep_id = r.id
          WHERE peran_saya() <> 'sales'::text OR r.id = sales_rep_saya()
          GROUP BY r.id, r.nama, r.jenis) v
  WHERE boleh_baca();
