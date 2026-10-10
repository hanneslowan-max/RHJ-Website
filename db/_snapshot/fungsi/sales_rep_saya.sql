CREATE OR REPLACE FUNCTION public.sales_rep_saya()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id from public.sales_reps where profile_id = auth.uid() limit 1
$function$;
