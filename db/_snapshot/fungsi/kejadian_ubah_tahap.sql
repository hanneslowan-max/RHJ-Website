CREATE OR REPLACE FUNCTION public.kejadian_ubah_tahap()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.hitung_ulang_tahap(coalesce(new.lead_id, old.lead_id));
  return null;
end $function$;
