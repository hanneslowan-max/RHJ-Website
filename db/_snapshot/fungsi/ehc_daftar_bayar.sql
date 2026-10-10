CREATE OR REPLACE FUNCTION public.ehc_daftar_bayar(p_bulan text, p_batch bigint DEFAULT NULL::bigint)
 RETURNS TABLE(klaim_id bigint, keadaan text, periode text, sales_rep_id bigint, sales text, customer text, lintas boolean, keperluan text, cara_bayar text, sumber_tujuan text, bank text, no_rekening text, atas_nama text, nominal numeric, sp jsonb, gm_nama text, gm_pada timestamp with time zone, batch_id bigint, ditransfer_pada timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare v_rek boolean := public.boleh_rekap_transfer();
begin
  if not public.boleh_lihat_nilai_klaim() then
    raise exception 'Anda tidak berhak melihat daftar bayar EHC.' using errcode = '42501';
  end if;
  if p_batch is null and (p_bulan is null or p_bulan !~ '^\d{4}-\d{2}$') then
    raise exception 'Periode harus dalam bentuk YYYY-MM.' using errcode = '22023';
  end if;
  return query
  select k.id, x.keadaan, k.periode, k.sales_rep_id, r.nama, c.nama, public.klaim_ehc_lintas(k.id),
         k.keperluan, k.cara_bayar, t.sumber,
         case when v_rek then t.bank end, case when v_rek then t.no_rekening end, case when v_rek then t.atas_nama end,
         n.nominal::numeric,
         (select coalesce(jsonb_agg(jsonb_build_object('so_id', a.so_id, 'no_sp', s.no_sp, 'nominal', a.nominal,
                                                       'lunas', s.lunas, 'batal', s.batal) order by a.so_id), '[]'::jsonb)
            from public.ehc_klaim_alokasi a join public.sales_orders s on s.id = a.so_id
           where a.klaim_id = k.id and a.nominal > 0),
         g.nama, k.gm_pada, k.transfer_batch_id, k.ditransfer_pada
    from public.ehc_klaim k
    cross join lateral (select public.ehc_keadaan_bayar(k, coalesce(p_bulan, k.periode)) as keadaan) x
    left join public.sales_reps r on r.id = k.sales_rep_id
    left join public.customers c on c.id = k.customer_id
    left join public.ehc_klaim_tujuan t on t.klaim_id = k.id
    left join public.ehc_klaim_nilai n on n.klaim_id = k.id
    left join public.profiles g on g.id = k.gm_oleh
   where (p_batch is null and x.keadaan in ('siap','menunggu_lunas','tanpa_rekening','menunggu_gm','cepat'))
      or (p_batch is not null and k.transfer_batch_id = p_batch)
   order by x.keadaan, r.nama, k.id;
end $function$;
