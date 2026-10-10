-- reloptions: (none)
create or replace view public.tautan_sales_tinjau as
 SELECT nama_sheet,
    pelanggan,
    belum_bertaut,
    rep_nama,
    rep_aktif,
    putusan
   FROM ( WITH per_nama AS (
                 SELECT norm_sales(c.salesman_teks) AS nama_norm,
                    min(btrim(c.salesman_teks)) AS nama_sheet,
                    count(*) AS pelanggan,
                    count(*) FILTER (WHERE c.sales_rep_id IS NULL) AS belum_bertaut
                   FROM customers c
                  WHERE norm_sales(c.salesman_teks) IS NOT NULL
                  GROUP BY (norm_sales(c.salesman_teks))
                ), cocok AS (
                 SELECT p.nama_norm,
                    p.nama_sheet,
                    p.pelanggan,
                    p.belum_bertaut,
                    ( SELECT count(*) AS count
                           FROM sales_reps r
                          WHERE norm_sales(r.nama) = p.nama_norm) AS jumlah_cocok,
                    ( SELECT r.id
                           FROM sales_reps r
                          WHERE norm_sales(r.nama) = p.nama_norm
                         LIMIT 1) AS rep_id,
                    ( SELECT r.nama
                           FROM sales_reps r
                          WHERE norm_sales(r.nama) = p.nama_norm
                         LIMIT 1) AS rep_nama,
                    ( SELECT r.aktif
                           FROM sales_reps r
                          WHERE norm_sales(r.nama) = p.nama_norm
                         LIMIT 1) AS rep_aktif
                   FROM per_nama p
                )
         SELECT cocok.nama_sheet,
            cocok.pelanggan,
            cocok.belum_bertaut,
            cocok.rep_nama,
            cocok.rep_aktif,
                CASE
                    WHEN cocok.nama_sheet ~ '[,/&;]|\mdan\M'::text THEN 'banyak nama dalam satu sel'::text
                    WHEN cocok.jumlah_cocok = 0 THEN 'nama tidak ada di master'::text
                    WHEN cocok.jumlah_cocok > 1 THEN 'nama ganda di master'::text
                    WHEN cocok.belum_bertaut = 0 THEN 'sudah bertaut semua'::text
                    ELSE 'cocok — siap ditautkan'::text
                END AS putusan
           FROM cocok) v
  WHERE boleh_baca();
