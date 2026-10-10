-- reloptions: security_invoker=on
create or replace view public.sales_beban as
 SELECT id,
    nama,
    jenis,
    aktif,
    profile_id IS NOT NULL AS punya_akun,
    ( SELECT count(*) AS count
           FROM customers c
          WHERE c.sales_rep_id = r.id) AS pelanggan,
    ( SELECT count(*) AS count
           FROM leads l
          WHERE l.sales_rep_id = r.id) AS lead,
    ( SELECT count(*) AS count
           FROM purchase_orders p
          WHERE p.sales_rep_id = r.id) AS po,
    ( SELECT count(*) AS count
           FROM sales_orders s
          WHERE s.sales_rep_id = r.id) AS sp,
    ( SELECT count(*) AS count
           FROM ehc_klaim k
          WHERE k.sales_rep_id = r.id) AS klaim_ehc,
    ( SELECT count(*) AS count
           FROM komisi_klaim k
          WHERE k.sales_rep_id = r.id) AS klaim_komisi
   FROM sales_reps r;
