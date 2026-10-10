-- reloptions: security_invoker=on
create or replace view public.komisi_belum_klaim as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.kepada,
    s.customer_id,
    s.sales_rep_id,
    s.lunas,
    s.tgl_lunas,
    s.telat,
    s.gm_pct,
    s.harga_ok,
    COALESCE(r.ada_bawah_list, false) AS ada_bawah_list,
    COALESCE(r.total_barang, 0::numeric) AS total_barang,
    komisi_berlaku(s.id) AS komisi,
    s.lunas AND NOT (COALESCE(r.ada_bawah_list, false) AND s.harga_ok IS NOT TRUE) AND NOT (s.telat AND s.gm_pct IS NULL) AS bisa_klaim,
        CASE
            WHEN NOT s.lunas THEN 'SP belum lunas'::text
            WHEN COALESCE(r.ada_bawah_list, false) AND s.harga_ok IS NOT TRUE THEN 'Ada baris di bawah price list yang belum diputus GM'::text
            WHEN s.telat AND s.gm_pct IS NULL THEN 'Invoice lewat 120 hari — GM belum menetapkan persentasenya'::text
            WHEN s.telat THEN 'Lunas, komisi memakai persentase yang ditetapkan GM'::text
            ELSE 'SP sudah lunas'::text
        END AS alasan
   FROM sales_orders s
     LEFT JOIN so_ringkas r ON r.so_id = s.id
  WHERE ((CURRENT_USER <> ALL (ARRAY['authenticated'::name, 'anon'::name])) OR ( SELECT boleh_lihat_nilai_klaim() AS boleh_lihat_nilai_klaim) OR (( SELECT peran_saya() AS peran_saya)) = 'sales'::text AND s.sales_rep_id = (( SELECT sales_rep_saya() AS sales_rep_saya))) AND NOT s.batal AND NOT (EXISTS ( SELECT 1
           FROM komisi_klaim k
          WHERE k.so_id = s.id));
