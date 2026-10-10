CREATE OR REPLACE FUNCTION public.cutoff_ehc(p_periode text)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select to_date(p_periode || '-18', 'YYYY-MM-DD')
$function$;
