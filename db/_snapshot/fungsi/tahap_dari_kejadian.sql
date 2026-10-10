CREATE OR REPLACE FUNCTION public.tahap_dari_kejadian(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when exists (select 1 from public.lead_events where lead_id = p_lead and jenis = 'batal')
         then 'Batal'
    when exists (select 1 from public.lead_events where lead_id = p_lead and jenis = 'order')
         then 'Deal'
    when exists (select 1 from public.lead_events where lead_id = p_lead and jenis = 'follow_up')
         then 'Menunggu Kabar'
    when exists (select 1 from public.lead_events where lead_id = p_lead and jenis = 'penawaran')
         then 'Penawaran Terkirim'
    else 'Lead Baru' end
$function$;
