CREATE OR REPLACE FUNCTION public.so_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin new.dibuat_oleh := auth.uid(); return new; end $function$;
