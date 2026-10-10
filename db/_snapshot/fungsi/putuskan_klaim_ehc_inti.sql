CREATE OR REPLACE FUNCTION public.putuskan_klaim_ehc_inti(p_klaim bigint, p_setuju boolean, p_catatan text, p_versi timestamp with time zone, p_massal boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim; v_cat text := nullif(btrim(coalesce(p_catatan, '')), ''); v_snap jsonb;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutus klaim EHC.' using errcode = '42501';
  end if;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC #% berstatus % — sudah diputus.', p_klaim, k.status using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim EHC #% sudah masuk batch transfer #%.', p_klaim, k.transfer_batch_id using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is distinct from false then
    raise exception 'Klaim EHC #% sedang meminta pencairan cepat — putuskan di antrean EHC cepat.', p_klaim
      using errcode = '22023';
  end if;
  if public.hari_ini_wib() <= public.cutoff_ehc(k.periode) then
    raise exception 'Klaim EHC periode % diperiksa GM sesudah tgl 18 (cutoff %). Kalau mendesak, sales meminta EHC cepat.',
      k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
  end if;
  if p_versi is null or p_versi <> coalesce(k.diubah_pada, k.dibuat_pada) then
    raise exception 'Klaim EHC #% berubah sejak dimuat — muat ulang lalu periksa lagi.', p_klaim using errcode = '40001';
  end if;
  if p_setuju is null then
    raise exception 'Pilih setujui atau tolak.' using errcode = '22023';
  end if;
  if not p_setuju and v_cat is null then
    raise exception 'Penolakan klaim EHC wajib beralasan — sales perlu tahu kenapa.' using errcode = '22023';
  end if;
  if p_massal and public.klaim_ehc_lintas(p_klaim) then
    raise exception 'Klaim EHC #% lintas customer — putuskan satu per satu.', p_klaim using errcode = '22023';
  end if;

  if p_setuju then
    v_snap := public.siapkan_setuju_klaim_ehc(p_klaim, 'periksa');
  else
    v_snap := public.snapshot_klaim_ehc(p_klaim);
  end if;
  update public.ehc_klaim
     set status = case when p_setuju then 'disetujui' else 'ditolak' end,
         gm_oleh = auth.uid(), gm_pada = now(), gm_catatan = v_cat, gm_jalur = 'periksa'
   where id = p_klaim;
  insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh)
  values (p_klaim, 'periksa', case when p_setuju then 'setuju' else 'tolak' end, v_cat, v_snap, auth.uid());
  return jsonb_build_object('klaim', p_klaim, 'setuju', p_setuju,
                            'nominal', v_snap->'nominal', 'alokasi', v_snap->'alokasi');
end $function$;
