CREATE OR REPLACE FUNCTION public.komisi_pct_baris(p_jenis text, p_flat numeric, p_ada_hk boolean, p_hk_pct numeric, p_cash_ok boolean, p_nett_dpp numeric, p_list numeric, p_hammer boolean)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_jenis = 'biaya'    then null
    when p_flat is not null   then p_flat
    when p_ada_hk             then p_hk_pct
    when p_cash_ok is true    then public.komisi_tier_cash(p_nett_dpp, p_list)
    else public.komisi_tier(p_nett_dpp, p_list, p_hammer)
  end
$function$;
