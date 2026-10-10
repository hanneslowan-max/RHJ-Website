CREATE OR REPLACE FUNCTION public.boleh_lihat_order_impor()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select public.boleh_lihat_impor() or public.peran_saya() = 'vonny'
$function$;
