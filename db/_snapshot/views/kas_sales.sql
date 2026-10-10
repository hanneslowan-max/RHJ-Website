-- reloptions: security_invoker=on
create or replace view public.kas_sales as
 SELECT v.sales_rep_id,
    r.nama AS sales,
    sum(v.sisa) AS saldo,
    count(*) AS jumlah_klaim
   FROM ehc_saldo_sp v
     LEFT JOIN sales_reps r ON r.id = v.sales_rep_id
  WHERE v.tertutup AND v.sisa > 0::numeric
  GROUP BY v.sales_rep_id, r.nama;
