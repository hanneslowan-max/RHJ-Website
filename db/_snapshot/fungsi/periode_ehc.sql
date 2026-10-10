CREATE OR REPLACE FUNCTION public.periode_ehc(p_tgl date)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select to_char(case when extract(day from p_tgl) <= 18 then p_tgl
                      else (date_trunc('month', p_tgl) + interval '1 month')::date end,
                 'YYYY-MM')
$function$;
