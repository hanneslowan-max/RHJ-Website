CREATE OR REPLACE FUNCTION public.bulan_romawi(b integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'])[b]
$function$;
