-- reloptions: (none)
create or replace view public.order_untuk_sales as
 SELECT id,
    no_invoice,
    tanggal_order,
    status_produksi,
    etd,
    eta,
    tanggal_tiba,
    status_dokumen,
    status_customs
   FROM ( SELECT o.id,
            o.no_invoice,
            o.tanggal_order,
            o.status_produksi,
            o.etd,
            o.eta,
            o.tanggal_tiba,
            o.status_dokumen,
            o.status_customs
           FROM orders o) v
  WHERE akun_disetujui();
