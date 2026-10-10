CREATE OR REPLACE FUNCTION public.jaga_total_sp_kepala()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.periksa_total_sp(new.id);
  return null;
end $function$;
