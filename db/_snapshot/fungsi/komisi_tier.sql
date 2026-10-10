CREATE OR REPLACE FUNCTION public.komisi_tier(p_nett numeric, p_list numeric, p_hammer boolean)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_list is null or p_list <= 0 then null      -- tak ada acuan
    when p_nett < p_list                then null     -- eskalasi GM
    when p_nett >= p_list * 1.10        then 0.05
    when p_nett >= p_list * 1.05        then case when p_hammer then 0.04 else 0.03 end
    else 0.02
  end
$function$;
