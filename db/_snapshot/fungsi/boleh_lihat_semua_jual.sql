CREATE OR REPLACE FUNCTION public.boleh_lihat_semua_jual()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.peran_saya() in ('owner','gm','staff','finance','liesian','ichi','vonny','lenni')
$function$;
