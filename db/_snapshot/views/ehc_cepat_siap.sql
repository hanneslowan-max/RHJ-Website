-- reloptions: security_invoker=on
create or replace view public.ehc_cepat_siap as
 SELECT k.id AS klaim_id,
    k.so_id,
    s.no_sp,
    s.kepada,
    k.sales_rep_id,
    r.nama AS sales,
    p.nama AS pic,
    k.cara_bayar,
    t.bank,
    t.no_rekening,
    t.atas_nama,
    k.tanggal,
    n.nominal,
    k.cepat_alasan,
    k.cepat_catatan,
    k.cepat_diputus_pada,
    klaim_ehc_terkunci_pengajuan(k.id) AS pengajuan_bulanan,
    k.customer_id,
    c.nama AS customer,
    k.keperluan,
    klaim_ehc_lintas(k.id) AS lintas_customer,
    klaim_ehc_tujuan_ada(k.id) AS rekening_ada,
    (EXISTS ( SELECT 1
           FROM ehc_klaim_alokasi a
             JOIN sales_orders so ON so.id = a.so_id
          WHERE a.klaim_id = k.id AND a.nominal > 0::numeric AND so.batal)) AS ada_sp_batal
   FROM ehc_klaim k
     LEFT JOIN sales_orders s ON s.id = k.so_id
     LEFT JOIN sales_reps r ON r.id = k.sales_rep_id
     LEFT JOIN customer_pics p ON p.id = k.pic_id
     LEFT JOIN ehc_klaim_nilai n ON n.klaim_id = k.id
     LEFT JOIN customers c ON c.id = k.customer_id
     LEFT JOIN ehc_klaim_tujuan t ON t.klaim_id = k.id
  WHERE k.status = 'disetujui'::text AND k.cepat_minta AND k.cepat_ok AND k.transfer_batch_id IS NULL;
