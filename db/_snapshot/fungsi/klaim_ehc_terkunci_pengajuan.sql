CREATE OR REPLACE FUNCTION public.klaim_ehc_terkunci_pengajuan(p_klaim bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select t.id from public.transfer_pengajuan t
   join public.transfer_pengajuan_baris b on b.pengajuan_id = t.id
  where t.jenis = 'ehc' and t.status in ('menunggu','disetujui') and b.klaim_id = p_klaim
  limit 1
$function$;
