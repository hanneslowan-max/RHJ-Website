CREATE OR REPLACE FUNCTION public.harga_berlaku_hitung(p_product bigint, p_tgl date DEFAULT CURRENT_DATE)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select harga from public.price_list
   where product_id = p_product and berlaku_dari <= p_tgl
   order by berlaku_dari desc, id desc limit 1
$function$;
