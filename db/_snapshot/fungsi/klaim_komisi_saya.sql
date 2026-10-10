CREATE OR REPLACE FUNCTION public.klaim_komisi_saya(p_klaim bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.peran_saya() = 'sales'
     and public.sales_rep_saya() is not null
     and exists (
       select 1 from public.komisi_klaim k
        where k.id = p_klaim
          and (k.sales_rep_id = public.sales_rep_saya()
               or exists (select 1 from public.sales_orders s
                           where s.id = k.so_id
                             and s.sales_rep_id = public.sales_rep_saya())))
$function$;
