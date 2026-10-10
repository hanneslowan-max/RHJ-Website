-- reloptions: security_invoker=on
create or replace view public.so_kirim_ringkas as
 SELECT so_id,
    count(*) AS jml_baris,
    sum(
        CASE
            WHEN sisa <= 0::numeric THEN 1
            ELSE 0
        END) AS baris_lengkap,
    COALESCE(bool_and(sisa <= 0::numeric), true) AS semua_terkirim,
    sum(qty_kirim) AS total_kirim,
    sum(qty_pesan) AS total_pesan
   FROM so_kirim_sisa z
  GROUP BY so_id;
