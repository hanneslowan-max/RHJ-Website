CREATE OR REPLACE FUNCTION public.siapkan_setuju_klaim_ehc(p_klaim bigint, p_jalur text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim; a record; v_sum numeric := 0; v_nom numeric;
        v_pic public.customer_pics; v_rek public.sales_rep_rekening;
        v_sumber text; v_bank text; v_norek text; v_an text;
begin
  select * into k from public.ehc_klaim where id = p_klaim;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if not exists (select 1 from public.ehc_klaim_berkas f where f.klaim_id = p_klaim and f.dibuang_pada is null) then
    raise exception 'Klaim tanpa lampiran tidak bisa disetujui — tolak dengan alasan.' using errcode = '22023';
  end if;
  perform 1 from public.sales_orders s
   where s.id in (select x.so_id from public.ehc_klaim_alokasi x where x.klaim_id = p_klaim and x.nominal > 0)
   order by s.id for update;
  for a in
    select x.so_id, x.nominal, s.no_sp, s.batal, trunc(coalesce(r.total_ehc, 0), 2) as total_ehc,
           (select coalesce(sum(y.nominal), 0) from public.ehc_klaim_alokasi y
              join public.ehc_klaim ky on ky.id = y.klaim_id
             where y.so_id = x.so_id and ky.status in ('diajukan','disetujui')) as terpakai
      from public.ehc_klaim_alokasi x
      join public.sales_orders s on s.id = x.so_id
      left join public.so_ringkas r on r.so_id = x.so_id
     where x.klaim_id = p_klaim and x.nominal > 0
     order by x.so_id
  loop
    if a.batal then
      raise exception 'SP % sudah dibatalkan — klaim ini tidak bisa disetujui. Tolak dengan alasan.', a.no_sp
        using errcode = '22023';
    end if;
    if a.total_ehc < a.terpakai then
      raise exception 'Saldo EHC SP % tidak cukup: EHC SP % sedangkan klaim aktif atas SP itu %.',
        a.no_sp, public.rp_teks(a.total_ehc), public.rp_teks(a.terpakai) using errcode = '23514';
    end if;
    v_sum := v_sum + a.nominal;
  end loop;
  select n.nominal into v_nom from public.ehc_klaim_nilai n where n.klaim_id = p_klaim;
  if v_sum = 0 or v_nom is distinct from v_sum then
    raise exception 'Nominal klaim EHC #% (%) tidak sama dengan jumlah alokasi SP-nya (%).',
      p_klaim, coalesce(public.rp_teks(v_nom), '-'), public.rp_teks(v_sum) using errcode = '23514';
  end if;

  if k.cara_bayar = 'transfer' then
    select * into v_pic from public.customer_pics where id = k.pic_id;
    if v_pic.id is null or not coalesce(v_pic.aktif, true) then
      raise exception 'PIC penerima transfer klaim ini sudah tidak aktif atau tidak ada — tolak dengan alasan.'
        using errcode = '22023';
    end if;
    if v_pic.customer_id is distinct from k.customer_id then
      raise exception 'PIC % bukan PIC customer penerima klaim ini.', v_pic.nama using errcode = '22023';
    end if;
    if coalesce(btrim(v_pic.bank), '') = '' or coalesce(btrim(v_pic.no_rekening), '') = '' then
      raise exception 'PIC % belum punya rekening.', v_pic.nama using errcode = '22023';
    end if;
    if exists (select 1 from public.sales_rep_rekening r
                where regexp_replace(r.no_rekening, '\D', '', 'g') = regexp_replace(v_pic.no_rekening, '\D', '', 'g')) then
      raise exception 'Rekening PIC % sama dengan rekening sales. Transfer ke customer harus ke rekening customer.',
        v_pic.nama using errcode = '42501';
    end if;
    v_sumber := 'pic'; v_bank := v_pic.bank; v_norek := v_pic.no_rekening; v_an := v_pic.atas_nama;
  elsif k.cara_bayar = 'reimburse' then
    select * into v_rek from public.sales_rep_rekening where sales_rep_id = k.sales_rep_id;
    if not found then
      raise exception 'Rekening sales belum diisi finance — klaim reimburse ini belum bisa disetujui.'
        using errcode = '22023';
    end if;
    v_sumber := 'sales'; v_bank := v_rek.bank; v_norek := v_rek.no_rekening; v_an := v_rek.atas_nama;
  elsif k.cara_bayar = 'tunai' then
    v_sumber := 'tunai';
  else
    raise exception 'Cara bayar % belum bisa diputus GM (kartu kredit perusahaan menyusul di tahap 2).', k.cara_bayar
      using errcode = '0A000';
  end if;

  insert into public.ehc_klaim_tujuan (klaim_id, sumber, pic_id, bank, no_rekening, atas_nama, dikunci_oleh)
  values (p_klaim, v_sumber, case when v_sumber = 'pic' then v_pic.id end, v_bank, v_norek, v_an, auth.uid());
  return public.snapshot_klaim_ehc(p_klaim)
      || jsonb_build_object('jalur', p_jalur,
                            'tujuan', jsonb_build_object('sumber', v_sumber, 'pic_id', case when v_sumber = 'pic' then v_pic.id end));
end $function$;
