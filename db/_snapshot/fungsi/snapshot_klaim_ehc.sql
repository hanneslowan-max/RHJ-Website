CREATE OR REPLACE FUNCTION public.snapshot_klaim_ehc(p_klaim bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'versi', coalesce(k.diubah_pada, k.dibuat_pada),
    'nominal', (select n.nominal from public.ehc_klaim_nilai n where n.klaim_id = k.id),
    'alokasi', (select coalesce(jsonb_agg(jsonb_build_object(
                  'so_id', a.so_id, 'no_sp', s.no_sp, 'nominal', a.nominal, 'lunas', s.lunas, 'batal', s.batal,
                  'total_ehc', trunc(coalesce(r.total_ehc, 0), 2),
                  'terpakai', (select coalesce(sum(x.nominal), 0) from public.ehc_klaim_alokasi x
                                 join public.ehc_klaim kx on kx.id = x.klaim_id
                                where x.so_id = a.so_id and kx.status in ('diajukan','disetujui')),
                  'tertutup', exists (select 1 from public.komisi_klaim kk where kk.so_id = a.so_id))
                  order by a.so_id), '[]'::jsonb)
                  from public.ehc_klaim_alokasi a
                  join public.sales_orders s on s.id = a.so_id
                  left join public.so_ringkas r on r.so_id = a.so_id
                 where a.klaim_id = k.id and a.nominal > 0),
    'lintas', public.klaim_ehc_lintas(k.id),
    'customer_id', k.customer_id, 'keperluan', k.keperluan, 'cara_bayar', k.cara_bayar,
    'berkas', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'path', f.path) order by f.id), '[]'::jsonb)
                 from public.ehc_klaim_berkas f where f.klaim_id = k.id and f.dibuang_pada is null),
    'cepat_alasan', k.cepat_alasan)
  from public.ehc_klaim k where k.id = p_klaim
$function$;
