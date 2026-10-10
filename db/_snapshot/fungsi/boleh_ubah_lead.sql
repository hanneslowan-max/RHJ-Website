CREATE OR REPLACE FUNCTION public.boleh_ubah_lead(p_lead bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.leads l
     where l.id = p_lead
       and (public.boleh_lihat_semua_lead()
            or (public.peran_saya() = 'sales' and l.sales_rep_id = public.sales_rep_saya()))
  )
$function$;
