CREATE OR REPLACE FUNCTION public.komisi_berlaku(p_so bigint)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.komisi_hitung(p_so) where public.boleh_lihat_komisi_sp(p_so)
$function$;
