CREATE OR REPLACE FUNCTION public.po_dobel(p_no text, p_kecuali bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.boleh_baca() then (
           select count(*)::int from public.purchase_orders
            where lower(btrim(no_po)) = lower(btrim(p_no))
              and (p_kecuali is null or id <> p_kecuali)
         ) end
$function$;
