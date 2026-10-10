CREATE OR REPLACE FUNCTION public.klaim_ehc_lintas(p_klaim bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.ehc_klaim k
                   join public.ehc_klaim_alokasi a on a.klaim_id = k.id
                   join public.sales_orders s on s.id = a.so_id
                  where k.id = p_klaim and a.nominal > 0 and s.customer_id is distinct from k.customer_id)
$function$;
