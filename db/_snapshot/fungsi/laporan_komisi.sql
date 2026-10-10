CREATE OR REPLACE FUNCTION public.laporan_komisi(p_dari date DEFAULT NULL::date, p_sampai date DEFAULT NULL::date)
 RETURNS TABLE(sales text, sales_rep_id bigint, jumlah_sp bigint, nilai_barang numeric, komisi_terhitung numeric, komisi_diklaim numeric, komisi_ditransfer numeric, ehc_terhitung numeric, ehc_diklaim numeric, ehc_ditransfer numeric, ehc_jadi_kas numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public.boleh_lihat_nilai_klaim() or public.peran_saya() = 'sales') then
    raise exception 'Anda tidak berwenang melihat nominal komisi dan EHC.'
      using errcode = '42501';
  end if;
  return query
  with saring as (select public.laporan_rep_saring() as rep),
       sp as (
         select s.id, s.sales_rep_id,
                coalesce(r.total_barang, 0) as total_barang,
                coalesce(r.komisi, 0)       as komisi,
                coalesce(r.total_ehc, 0)    as ehc
           from public.sales_orders s
           cross join saring
           left join public.so_ringkas r on r.so_id = s.id
          where not s.batal
            and s.lunas
            and s.tgl_lunas is not null
            and (p_dari   is null or s.tgl_lunas >= p_dari)
            and (p_sampai is null or s.tgl_lunas <= p_sampai)
            and (saring.rep is null or s.sales_rep_id = saring.rep)
       ),
       -- Klaim dihitung dari SP yang sama, supaya tiga angkanya benar-benar
       -- sebanding. Klaim atas SP di luar periode sengaja tidak ikut.
       kk as (
         select k.sales_rep_id,
                sum(coalesce(n.nominal, 0))                                   as diklaim,
                sum(case when k.transfer_batch_id is not null
                         then coalesce(n.nominal, 0) else 0 end)              as ditransfer
           from public.komisi_klaim k
           join sp on sp.id = k.so_id
           left join public.komisi_klaim_nilai n on n.klaim_id = k.id
          group by k.sales_rep_id
       ),
       ek as (
         select sp.sales_rep_id,
                sum(a.nominal)                                                as diklaim,
                sum(case when k.transfer_batch_id is not null
                         then a.nominal else 0 end)                           as ditransfer
           from public.ehc_klaim_alokasi a
           join public.ehc_klaim k on k.id = a.klaim_id and k.status in ('diajukan','disetujui')
           join sp on sp.id = a.so_id
          group by sp.sales_rep_id
       ),
       ekas as (
         select sp.sales_rep_id,
                sum(greatest(trunc(sp.ehc, 2)
                             - coalesce((select sum(a.nominal) from public.ehc_klaim_alokasi a
                                           join public.ehc_klaim k on k.id = a.klaim_id
                                          where a.so_id = sp.id
                                            and k.status in ('diajukan','disetujui')), 0), 0)) as kas
           from sp
          where exists (select 1 from public.komisi_klaim kk2 where kk2.so_id = sp.id)
          group by sp.sales_rep_id
       )
  select coalesce(r.nama, '(tanpa sales)')  as sales,
         sp.sales_rep_id,
         count(*)                            as jumlah_sp,
         sum(sp.total_barang)                as nilai_barang,
         sum(sp.komisi)                      as komisi_terhitung,
         coalesce(max(kk.diklaim), 0)        as komisi_diklaim,
         coalesce(max(kk.ditransfer), 0)     as komisi_ditransfer,
         sum(sp.ehc)                         as ehc_terhitung,
         coalesce(max(ek.diklaim), 0)        as ehc_diklaim,
         coalesce(max(ek.ditransfer), 0)     as ehc_ditransfer,
         coalesce(max(ekas.kas), 0)          as ehc_jadi_kas
    from sp
    left join public.sales_reps r on r.id = sp.sales_rep_id
    left join kk on kk.sales_rep_id = sp.sales_rep_id
    left join ek on ek.sales_rep_id = sp.sales_rep_id
    left join ekas on ekas.sales_rep_id = sp.sales_rep_id
   group by r.nama, sp.sales_rep_id
   order by 5 desc;
end $function$;
