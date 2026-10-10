CREATE OR REPLACE FUNCTION public.sp_pelanggan_hitam(p_customer bigint, p_po bigint, p_kepada text, p_telp text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id from public.sp_pelanggan_hitam_rinci(p_customer, p_po, p_kepada, p_telp) r limit 1
$function$;
