CREATE OR REPLACE FUNCTION public.hpp_berlaku(p_product bigint, p_tgl date DEFAULT CURRENT_DATE)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select hpp from public.product_costs
   where product_id = p_product and berlaku_dari <= p_tgl
     and public.boleh_lihat_hpp()
   order by berlaku_dari desc, id desc limit 1
$function$;
