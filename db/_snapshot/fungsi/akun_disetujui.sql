CREATE OR REPLACE FUNCTION public.akun_disetujui()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select auth.uid() is null or public.peran_saya() not in ('pending','nonaktif')
$function$;
