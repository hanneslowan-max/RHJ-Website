CREATE OR REPLACE FUNCTION public.hari_ini_wib()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select (now() at time zone 'Asia/Jakarta')::date
$function$;
