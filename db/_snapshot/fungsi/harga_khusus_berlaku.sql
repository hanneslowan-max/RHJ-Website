CREATE OR REPLACE FUNCTION public.harga_khusus_berlaku(p_customer bigint, p_product bigint, p_nett numeric)
 RETURNS harga_khusus
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select h.* from public.harga_khusus h
   where h.status = 'aktif'
     and h.customer_id = p_customer
     and h.product_id = p_product
     and p_nett >= h.harga_nett      -- batas bawah, bukan harga pasti
   limit 1
$function$;
