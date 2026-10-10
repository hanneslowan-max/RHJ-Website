CREATE OR REPLACE FUNCTION public.komisi_sp_saya(p_ids bigint[])
 RETURNS TABLE(so_id bigint, komisi numeric, diklaim boolean, menunggu_gm boolean, n_bawah_list integer, n_tanpa_list integer, telat boolean, batal boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then raise exception 'Belum masuk.' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 1000 then
    raise exception 'Terlalu banyak SP sekaligus (maks 1000).' using errcode = '22023';
  end if;
  return query
    select s.id,
           case when s.batal then null else coalesce(kk.nominal, public.komisi_hitung(s.id)) end,
           kk.id is not null,
           coalesce(r.ada_bawah_list, false) and s.harga_ok is null and not s.batal,
           coalesce(r.n_bawah_list, 0)::int, coalesce(r.n_tanpa_list, 0)::int,
           coalesce(s.telat, false), s.batal
      from (select distinct unnest(p_ids) as id) x
      join public.sales_orders s on s.id = x.id
      left join public.so_ringkas r on r.so_id = s.id
      left join lateral (select k.id, n.nominal from public.komisi_klaim k
                           left join public.komisi_klaim_nilai n on n.klaim_id = k.id
                          where k.so_id = s.id order by k.id desc limit 1) kk on true
     where public.boleh_lihat_hpp()
        or (public.peran_saya() = 'sales' and s.sales_rep_id = public.sales_rep_saya());
end $function$;
