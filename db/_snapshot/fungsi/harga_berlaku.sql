CREATE OR REPLACE FUNCTION public.harga_berlaku(p_product bigint, p_tgl date DEFAULT CURRENT_DATE)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.harga_berlaku_hitung(p_product, p_tgl)
   where public.boleh_lihat_harga_jual()
$function$;
