CREATE OR REPLACE FUNCTION public.batalkan_klaim_ehc(p_klaim bigint, p_alasan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim; v_alasan text := nullif(btrim(coalesce(p_alasan, '')), '');
        v_lewat boolean;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak membatalkan klaim EHC.' using errcode = '42501';
  end if;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if not (public.klaim_ehc_saya(p_klaim) or public.peran_saya() in ('owner','gm','staff')) then
    raise exception 'Klaim EHC ini bukan milik Anda.' using errcode = '42501';
  end if;
  if k.status not in ('diajukan','disetujui') then
    raise exception 'Klaim EHC ini berstatus %, tidak bisa dibatalkan.', k.status using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim EHC ini ada di batch transfer #% — %.', k.transfer_batch_id,
      case when k.ditransfer_pada is null then 'keluarkan dulu dari batch (finance) bila transfernya gagal'
           else 'uangnya sudah keluar' end using errcode = '22023';
  end if;
  if public.klaim_ehc_terkunci_pengajuan(p_klaim) is not null then
    raise exception 'Klaim EHC ini sudah masuk pengajuan transfer. Tarik dulu pengajuannya.' using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is null then
    raise exception 'Klaim ini sedang diajukan sebagai EHC cepat dan menunggu GM. Tarik permintaan cepatnya dulu.'
      using errcode = '22023';
  end if;
  v_lewat := public.hari_ini_wib() > public.cutoff_ehc(k.periode);
  if (v_lewat or k.status = 'disetujui') and not public.boleh_approve() then
    raise exception 'Periode % sudah lewat cutoff (%) atau klaim sudah disetujui. Pembatalan sekarang hanya oleh GM/owner.',
                    k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
  end if;
  if v_alasan is null then
    raise exception 'Alasan pembatalan wajib diisi.' using errcode = '22023';
  end if;
  update public.ehc_klaim
     set status = 'batal', batal_alasan = v_alasan, batal_oleh = auth.uid(), batal_pada = now()
   where id = p_klaim;
  insert into public.ehc_klaim_log (klaim_id, aksi, catatan, oleh)
  values (p_klaim, 'batal',
          v_alasan || case when k.status = 'disetujui' then ' (dibatalkan GM/owner sesudah disetujui)'
                           when v_lewat then ' (dibatalkan GM/owner sesudah cutoff)' else '' end, auth.uid());
  return 'Klaim EHC dibatalkan. Saldo EHC SP-nya kembali dan bisa dipakai lagi.';
end $function$;
