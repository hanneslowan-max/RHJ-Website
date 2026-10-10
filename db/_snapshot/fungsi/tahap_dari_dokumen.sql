CREATE OR REPLACE FUNCTION public.tahap_dari_dokumen(p_order bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o record; n_kirim int; ada_pi boolean; ada_do boolean;
begin
  select no_proforma, no_do into o from public.orders where id = p_order;
  if not found then return 'Order Diterima'; end if;

  select count(distinct jenis) into n_kirim from public.documents
   where order_id = p_order
     and jenis in ('Commercial Invoice','Packing List',
                   'Certificate of Origin','Bill of Lading');

  select exists (select 1 from public.documents
                  where order_id = p_order and jenis = 'Proforma Invoice') into ada_pi;
  select exists (select 1 from public.documents
                  where order_id = p_order and jenis = 'Delivery Order')   into ada_do;

  -- Dari yang paling jauh ke yang paling dekat.
  if coalesce(btrim(o.no_do), '') <> '' and ada_do and n_kirim = 4 then
    return 'Proses Customs';
  end if;
  if n_kirim = 4 then
    return 'Dalam Pengiriman';
  end if;
  if coalesce(btrim(o.no_proforma), '') <> '' and ada_pi then
    return 'Proses Produksi';
  end if;
  return 'Order Diterima';
end $function$;
