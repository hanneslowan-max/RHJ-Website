CREATE OR REPLACE FUNCTION public.status_sp(p_so bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.status_sp_hitung(p_so) where public.boleh_lihat_sp(p_so)
$function$;
