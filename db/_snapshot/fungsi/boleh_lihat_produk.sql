CREATE OR REPLACE FUNCTION public.boleh_lihat_produk()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.boleh_lihat_harga() or public.peran_saya() = 'selfie'
$function$;
