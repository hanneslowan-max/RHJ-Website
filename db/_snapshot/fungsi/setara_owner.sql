CREATE OR REPLACE FUNCTION public.setara_owner()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select public.peran_saya() in ('owner','gm') $function$;
