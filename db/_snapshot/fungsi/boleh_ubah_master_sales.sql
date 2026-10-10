CREATE OR REPLACE FUNCTION public.boleh_ubah_master_sales()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.peran_saya() in ('owner','gm') or auth.uid() is null
$function$;
