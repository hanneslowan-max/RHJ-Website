CREATE OR REPLACE FUNCTION public.pelanggan_saya(p_customer bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_customer is null or public.pic_pelanggan_saya(p_customer)
$function$;
