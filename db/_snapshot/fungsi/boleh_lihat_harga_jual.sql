CREATE OR REPLACE FUNCTION public.boleh_lihat_harga_jual()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.akun_disetujui()
$function$;
