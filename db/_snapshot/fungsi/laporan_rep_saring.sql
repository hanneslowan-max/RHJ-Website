CREATE OR REPLACE FUNCTION public.laporan_rep_saring()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- null = tanpa saringan (boleh lihat semua). Angka = hanya sales itu.
  select case when public.peran_saya() = 'sales'
              then coalesce(public.sales_rep_saya(), -1)
              else null end
$function$;
