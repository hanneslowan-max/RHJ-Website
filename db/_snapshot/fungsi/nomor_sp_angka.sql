CREATE OR REPLACE FUNCTION public.nomor_sp_angka(p_no integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select case when p_no < 1000 then lpad(p_no::text, 3, '0') else p_no::text end
$function$;
