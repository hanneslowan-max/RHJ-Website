CREATE OR REPLACE FUNCTION public.hitung_ulang_tahap(p_lead bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform set_config('rhj.crm', '1', true);
  update public.leads set tahap = public.tahap_dari_kejadian(p_lead) where id = p_lead;
  perform set_config('rhj.crm', '', true);
end $function$;
