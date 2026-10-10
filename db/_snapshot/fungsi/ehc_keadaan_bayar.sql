CREATE OR REPLACE FUNCTION public.ehc_keadaan_bayar(k ehc_klaim, p_bulan text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when k.transfer_batch_id is not null then case when k.ditransfer_pada is null then 'dibatch' else 'ditransfer' end
    when k.status = 'diajukan' then
      case when k.periode <= p_bulan and public.hari_ini_wib() > public.cutoff_ehc(k.periode)
                and not (k.cepat_minta and k.cepat_ok is null) then 'menunggu_gm' end
    when k.status <> 'disetujui' then null
    when k.cepat_minta and k.cepat_ok then 'cepat'
    when k.periode > p_bulan then null
    when not exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id) then 'tanpa_rekening'
    when exists (select 1 from public.ehc_klaim_alokasi a join public.sales_orders s on s.id = a.so_id
                  where a.klaim_id = k.id and a.nominal > 0 and (not s.lunas or s.batal)) then 'menunggu_lunas'
    when k.id in (select public.ehc_klaim_siap_transfer(p_bulan)) then 'siap'
    else 'tertahan' end
$function$;
