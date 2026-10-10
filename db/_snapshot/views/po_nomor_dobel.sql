-- reloptions: security_invoker=on
create or replace view public.po_nomor_dobel as
 SELECT lower(btrim(no_po)) AS no_po_kunci,
    min(no_po) AS no_po,
    count(*) AS jumlah,
    max(tanggal) AS terakhir,
    string_agg(DISTINCT nama_customer, ' · '::text ORDER BY nama_customer) AS perusahaan
   FROM purchase_orders p
  WHERE COALESCE(btrim(no_po), ''::text) <> ''::text AND NOT batal
  GROUP BY (lower(btrim(no_po)))
 HAVING count(*) > 1;
