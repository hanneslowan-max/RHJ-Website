CREATE OR REPLACE FUNCTION public.boleh_minta_klaim_cepat(p_klaim bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.peran_saya() in ('owner','gm','staff','finance')
      or public.klaim_ehc_saya(p_klaim)
$function$;
