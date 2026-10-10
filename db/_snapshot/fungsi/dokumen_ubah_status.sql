CREATE OR REPLACE FUNCTION public.dokumen_ubah_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.hitung_ulang_status(coalesce(new.order_id, old.order_id));
  return coalesce(new, old);
end $function$;
