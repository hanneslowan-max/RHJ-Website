-- reloptions: security_invoker=on
create or replace view public.ehc_saldo_sp as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.kepada,
    s.customer_id,
    c.nama AS customer,
    s.sales_rep_id,
    s.lunas,
    s.tgl_lunas,
    trunc(COALESCE(r.total_ehc, 0::numeric), 2) AS total_ehc,
    COALESCE(a.terpakai, 0::numeric) AS terpakai,
    trunc(COALESCE(r.total_ehc, 0::numeric), 2) - COALESCE(a.terpakai, 0::numeric) AS sisa,
    COALESCE(a.jumlah_klaim, 0::bigint) AS jumlah_klaim,
    (EXISTS ( SELECT 1
           FROM komisi_klaim kk
          WHERE kk.so_id = s.id)) AS tertutup
   FROM sales_orders s
     LEFT JOIN so_ringkas r ON r.so_id = s.id
     LEFT JOIN customers c ON c.id = s.customer_id
     LEFT JOIN LATERAL ( SELECT sum(x.nominal) AS terpakai,
            count(DISTINCT x.klaim_id) FILTER (WHERE x.nominal > 0::numeric) AS jumlah_klaim
           FROM ehc_klaim_alokasi x
             JOIN ehc_klaim k ON k.id = x.klaim_id
          WHERE x.so_id = s.id AND (k.status = ANY (ARRAY['diajukan'::text, 'disetujui'::text]))) a ON true
  WHERE NOT s.batal AND (( SELECT boleh_lihat_nilai_klaim() AS boleh_lihat_nilai_klaim) OR (( SELECT peran_saya() AS peran_saya)) = 'sales'::text AND s.sales_rep_id = (( SELECT sales_rep_saya() AS sales_rep_saya)));
