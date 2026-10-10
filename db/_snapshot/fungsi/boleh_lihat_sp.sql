CREATE OR REPLACE FUNCTION public.boleh_lihat_sp(p_so bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.sales_orders s
     where s.id = p_so
       and (public.boleh_lihat_semua_jual()
            or (public.peran_saya() = 'sales' and s.sales_rep_id = public.sales_rep_saya()))
  )
$function$;
