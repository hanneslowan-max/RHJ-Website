CREATE OR REPLACE FUNCTION public.klaim_ehc_tujuan_ada(p_klaim bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (public.boleh_lihat_nilai_klaim() or public.klaim_ehc_saya(p_klaim))
     and exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = p_klaim)
$function$;
