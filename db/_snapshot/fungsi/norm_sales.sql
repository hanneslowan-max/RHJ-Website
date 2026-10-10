CREATE OR REPLACE FUNCTION public.norm_sales(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select nullif(upper(btrim(regexp_replace(coalesce(t, ''), '\s+', ' ', 'g'))), '')
$function$;
