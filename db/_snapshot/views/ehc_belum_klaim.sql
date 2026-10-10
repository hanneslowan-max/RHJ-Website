-- reloptions: security_invoker=on
create or replace view public.ehc_belum_klaim as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.kepada,
    s.customer_id,
    s.sales_rep_id,
    s.lunas,
    s.tgl_lunas,
    s.ehc_dini_minta,
    s.ehc_dini_ok,
    COALESCE(r.total_ehc, 0::numeric) AS total_ehc,
    s.lunas OR s.ehc_dini_ok AS bisa_klaim,
        CASE
            WHEN s.lunas THEN 'SP sudah lunas'::text
            WHEN s.ehc_dini_ok THEN 'Klaim dini disetujui GM'::text
            WHEN s.ehc_dini_minta THEN 'Menunggu putusan GM untuk klaim dini'::text
            ELSE 'SP belum lunas'::text
        END AS alasan
   FROM sales_orders s
     LEFT JOIN so_ringkas r ON r.so_id = s.id
  WHERE NOT s.batal AND NOT (EXISTS ( SELECT 1
           FROM ehc_klaim k
          WHERE k.so_id = s.id));
