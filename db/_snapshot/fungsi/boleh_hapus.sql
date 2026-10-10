CREATE OR REPLACE FUNCTION public.boleh_hapus()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select public.peran_saya() = 'owner' $function$;
