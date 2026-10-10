CREATE OR REPLACE FUNCTION public.ehc_klaim_siap_transfer(p_bulan text)
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select k.id from public.ehc_klaim k
   where k.status = 'disetujui'
     and k.transfer_batch_id is null
     and k.periode <= p_bulan
     and k.cara_bayar in ('transfer','reimburse','tunai')
     and exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id)
     and not (k.cepat_minta and k.cepat_ok is distinct from false)
     and public.klaim_ehc_terkunci_pengajuan(k.id) is null
     and exists (select 1 from public.ehc_klaim_alokasi a where a.klaim_id = k.id and a.nominal > 0)
     and exists (select 1 from public.ehc_klaim_berkas f where f.klaim_id = k.id and f.dibuang_pada is null)
     and not exists (select 1 from public.ehc_klaim_alokasi a
                       join public.sales_orders s on s.id = a.so_id
                      where a.klaim_id = k.id and a.nominal > 0 and (not s.lunas or s.batal))
$function$;
