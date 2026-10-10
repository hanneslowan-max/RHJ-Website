CREATE OR REPLACE FUNCTION public.daftar_grup_pelanggan()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_owner boolean := public.setara_owner(); v_saya bigint := public.sales_rep_saya();
begin
  if auth.uid() is null or not public.boleh_baca() then
    raise exception 'Anda tidak berwenang melihat grup pelanggan.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x.g order by lower(x.g->>'nama'))
      from (select jsonb_build_object(
                     'id', g.id, 'nama', g.nama, 'nama_dokumen', g.nama_dokumen, 'catatan', g.catatan,
                     'anggota', coalesce((
                        select jsonb_agg(
                                 jsonb_build_object('customer_id', c.id, 'nama', c.nama, 'cabang', c.cabang,
                                                    'sales_rep_id', c.sales_rep_id,
                                                    'sales_nama', sr.nama || case when sr.aktif then '' else ' (nonaktif)' end,
                                                    'milik_saya', v_saya is not null and c.sales_rep_id = v_saya)
                                 || case when v_owner then (
                                      select jsonb_build_object(
                                               'jumlah_sp', count(*) filter (where not s.batal),
                                               'penjualan', coalesce(sum(r.grand_total) filter (where not s.batal), 0),
                                               'penjualan_tahun_ini', coalesce(sum(r.grand_total) filter (
                                                    where not s.batal and s.tanggal >= date_trunc('year', current_date)::date), 0),
                                               'piutang', coalesce(sum(r.grand_total) filter (
                                                    where not s.batal and s.no_invoice is not null and s.tgl_invoice is not null
                                                      and not s.lunas), 0))
                                        from public.sales_orders s
                                        left join public.so_ringkas r on r.so_id = s.id
                                       where s.customer_id = c.id)
                                    else '{}'::jsonb end
                                 order by c.nama_urut, c.id)
                          from public.customers c
                          left join public.sales_reps sr on sr.id = c.sales_rep_id
                         where c.grup_id = g.id), '[]'::jsonb)) as g
              from public.customer_groups g) x), '[]'::jsonb);
end $function$;
