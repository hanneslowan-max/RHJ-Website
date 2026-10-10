-- reloptions: security_invoker=on
create or replace view public.usulan_produk as
 SELECT id,
    usulan_teks,
    kode,
    brand,
    satuan,
    dibuat_pada,
    dibuat_oleh,
    dipakai_po,
    dipakai_sp,
    customer,
    qty_diminta
   FROM ( SELECT p.id,
            p.usulan_teks,
            p.kode,
            p.brand,
            p.satuan,
            p.dibuat_pada,
            p.dibuat_oleh,
            ( SELECT count(DISTINCT x.po_id) AS count
                   FROM po_lines x
                  WHERE x.product_id = p.id) AS dipakai_po,
            ( SELECT count(DISTINCT s.so_id) AS count
                   FROM sales_order_lines s
                  WHERE s.product_id = p.id) AS dipakai_sp,
            ( SELECT string_agg(DISTINCT o.nama_customer, ', '::text) AS string_agg
                   FROM po_lines x
                     JOIN purchase_orders o ON o.id = x.po_id
                  WHERE x.product_id = p.id) AS customer,
            ( SELECT COALESCE(sum(x.qty), 0::numeric) AS "coalesce"
                   FROM po_lines x
                  WHERE x.product_id = p.id) AS qty_diminta
           FROM products p
          WHERE p.usulan AND ((EXISTS ( SELECT 1
                   FROM po_lines x2
                  WHERE x2.product_id = p.id)) OR (EXISTS ( SELECT 1
                   FROM sales_order_lines s2
                  WHERE s2.product_id = p.id)) OR NOT (EXISTS ( SELECT 1
                   FROM quote_lines q
                  WHERE q.product_id = p.id)))) v
  WHERE ( SELECT akun_disetujui() AS akun_disetujui) AND (( SELECT boleh_ubah_impor() AS boleh_ubah_impor) OR dibuat_oleh = (( SELECT auth.uid() AS uid)) OR dipakai_po > 0 OR dipakai_sp > 0);
