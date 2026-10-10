CREATE OR REPLACE FUNCTION public.komisi_tier_cash(p_nett numeric, p_list numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_list is null or p_list <= 0 then null   -- tak ada acuan → GM
    when p_nett < p_list               then null   -- di bawah list → GM
    else 0.05                                      -- di list atau di atasnya
  end
$function$;
