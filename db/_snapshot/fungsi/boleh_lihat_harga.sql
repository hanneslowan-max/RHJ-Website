CREATE OR REPLACE FUNCTION public.boleh_lihat_harga()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select public.peran_saya() in ('owner','gm','staff','finance','sales','vonny','lenni') $function$;
