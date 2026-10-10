CREATE OR REPLACE FUNCTION public.periksa_saldo_ehc_sp(p_so bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_terpakai numeric; v_belum numeric; v_total numeric; v_batal boolean; v_no text;
begin
  if p_so is null then return; end if;
  select coalesce(sum(a.nominal), 0),
         coalesce(sum(a.nominal) filter (where k.ditransfer_pada is null), 0)
    into v_terpakai, v_belum
    from public.ehc_klaim_alokasi a join public.ehc_klaim k on k.id = a.klaim_id
   where a.so_id = p_so and k.status in ('diajukan','disetujui');
  if v_terpakai = 0 then return; end if;

  select s.batal, s.no_sp into v_batal, v_no from public.sales_orders s where s.id = p_so;
  if not found then return; end if;
  if v_batal then
    if v_belum > 0 then
      raise exception 'SP % tidak bisa dibatalkan: saldo EHC-nya masih dipakai klaim EHC yang belum dibayar (%). '
                      'Batalkan klaim EHC-nya dulu — sales sebelum cutoff, owner/GM kapan saja.',
                      v_no, public.rp_teks(v_belum) using errcode = '23514';
    end if;
    return;
  end if;
  select trunc(coalesce(r.total_ehc, 0), 2) into v_total from public.so_ringkas r where r.so_id = p_so;
  if coalesce(v_total, 0) < v_terpakai then
    raise exception 'EHC SP % tinggal % sesudah perubahan ini, padahal klaim EHC aktif atas SP ini sudah %. '
                    'Ubah atau batalkan klaim EHC-nya dulu.',
                    v_no, public.rp_teks(coalesce(v_total, 0)), public.rp_teks(v_terpakai)
      using errcode = '23514';
  end if;
end $function$;
