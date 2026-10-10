-- reloptions: security_invoker=on
create or replace view public.product_set_ringkas as
 SELECT s.id,
    s.kode,
    s.nama,
    s.kategori,
    s.catatan,
    s.aktif,
    COALESCE(sum(c.qty * c.harga_nett), 0::numeric) AS harga_set,
    COALESCE(sum(c.qty), 0::numeric) AS total_pcs,
    count(c.id) AS jumlah_komponen
   FROM product_sets s
     LEFT JOIN product_set_components c ON c.set_id = s.id
  GROUP BY s.id;
