CREATE OR REPLACE FUNCTION public.peran_saya()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select peran from public.profiles where id = auth.uid()), 'pending');
$function$;
