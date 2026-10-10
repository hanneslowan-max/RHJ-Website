CREATE OR REPLACE FUNCTION public.putuskan_klaim_cepat_v(p_klaim bigint, p_setuju boolean, p_catatan text DEFAULT NULL::text, p_versi timestamp with time zone DEFAULT NULL::timestamp with time zone, p_diminta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim; v_cat text; v_sp text; v_pj bigint; v_snap jsonb;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan pencairan cepat.' using errcode = '42501';
  end if;
  v_cat := nullif(btrim(coalesce(p_catatan, '')), '');
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then
    raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002';
  end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC #% berstatus % — tidak bisa diputus lagi.', p_klaim, k.status using errcode = '22023';
  end if;
  if not k.cepat_minta or k.cepat_ok is not null then
    raise exception 'Klaim #% tidak sedang menunggu putusan pencairan cepat.', p_klaim using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim #% sudah ditransfer lewat batch #%.', p_klaim, k.transfer_batch_id using errcode = '22023';
  end if;
  if p_setuju is null then
    raise exception 'Pilih setujui atau tolak.' using errcode = '22023';
  end if;
  if p_setuju and (p_versi is null or p_versi <> coalesce(k.diubah_pada, k.dibuat_pada)
                   or p_diminta is null or p_diminta is distinct from k.cepat_diminta_pada) then
    raise exception 'Klaim EHC #% berubah atau permintaan cepatnya diajukan ulang sejak dimuat — muat ulang lalu periksa lagi.', p_klaim
      using errcode = '40001';
  end if;
  if not p_setuju and v_cat is null then
    raise exception 'Penolakan wajib beralasan — sales-nya harus bisa menjelaskan ke '
                    'pelanggannya kenapa tidak bisa dipercepat.' using errcode = '22023';
  end if;
  if p_setuju then
    v_pj := public.klaim_ehc_terkunci_pengajuan(p_klaim);
    if v_pj is not null then
      raise exception 'Klaim #% masih terkunci di pengajuan transfer bulanan #%. Tarik dulu pengajuan itu.',
        p_klaim, v_pj using errcode = '22023';
    end if;
    v_snap := public.siapkan_setuju_klaim_ehc(p_klaim, 'cepat');
  end if;

  perform set_config('rhj.cepat', 'on', true);
  if p_setuju then
    update public.ehc_klaim
       set cepat_ok = true, cepat_catatan = v_cat, cepat_diputus_oleh = auth.uid(), cepat_diputus_pada = now(),
           cepat_minta = true, status = 'disetujui',
           gm_oleh = auth.uid(), gm_pada = now(), gm_catatan = v_cat, gm_jalur = 'cepat'
     where id = p_klaim;
  else
    update public.ehc_klaim
       set cepat_ok = false, cepat_catatan = v_cat, cepat_diputus_oleh = auth.uid(), cepat_diputus_pada = now(),
           cepat_minta = true
     where id = p_klaim;
  end if;
  perform set_config('rhj.cepat', 'off', true);

  insert into public.ehc_cepat_log (klaim_id, aksi, alasan, oleh)
  values (p_klaim, case when p_setuju then 'setuju' else 'tolak' end, v_cat, auth.uid());
  if p_setuju then
    insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh)
    values (p_klaim, 'cepat', 'setuju', v_cat, v_snap, auth.uid());
  end if;

  select no_sp into v_sp from public.sales_orders where id = k.so_id;
  return case when p_setuju
    then 'Klaim EHC ' || coalesce(v_sp, '#' || p_klaim) || ' DISETUJUI untuk dicairkan cepat. '
       || 'Finance melihatnya lewat tombol "EHC emergency" di Laporan Finance.'
    else 'Permintaan klaim cepat untuk ' || coalesce(v_sp, '#' || p_klaim) || ' DITOLAK. '
       || 'Klaimnya tetap diajukan dan diperiksa GM sesudah tgl 18 seperti biasa.'
  end;
end $function$;
