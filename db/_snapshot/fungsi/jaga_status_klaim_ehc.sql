CREATE OR REPLACE FUNCTION public.jaga_status_klaim_ehc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_batch boolean := coalesce(current_setting('rhj.batch', true), '') = 'on';
  v_bebas text[] := array['sales_rep_id','status','batal_alasan','batal_oleh','batal_pada',
                          'transfer_batch_id','ditransfer_pada'];
begin
  if tg_op = 'INSERT' then
    if new.status <> 'diajukan' or new.transfer_batch_id is not null or new.ditransfer_pada is not null
       or new.gm_oleh is not null or new.gm_pada is not null or new.gm_catatan is not null or new.gm_jalur is not null then
      raise exception 'Klaim EHC baru selalu berstatus diajukan, tanpa putusan GM dan tanpa batch.' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.status is distinct from old.status
     and not ((old.status = 'diajukan' and new.status in ('disetujui','ditolak','batal'))
              or (old.status = 'disetujui' and new.status = 'batal' and old.transfer_batch_id is null)) then
    raise exception 'Status klaim EHC #% tidak bisa berpindah dari % ke %.', old.id, old.status, new.status
      using errcode = '42501';
  end if;
  if new.cepat_ok is true and old.cepat_ok is distinct from true and new.status = 'diajukan' then
    raise exception 'Persetujuan EHC cepat klaim #% harus sekaligus memutus klaimnya (putuskan_klaim_cepat_v, berkas 142) — muat ulang halaman.', old.id
      using errcode = '42501';
  end if;
  if (new.gm_oleh, new.gm_pada, new.gm_catatan, new.gm_jalur)
       is distinct from (old.gm_oleh, old.gm_pada, old.gm_catatan, old.gm_jalur)
     and not (old.status = 'diajukan' and new.status in ('disetujui','ditolak')) then
    raise exception 'Putusan GM klaim EHC #% tidak bisa diubah — putusan hanya lewat putuskan_klaim_ehc / putuskan_klaim_cepat.', old.id
      using errcode = '42501';
  end if;
  if (new.batal_alasan, new.batal_oleh, new.batal_pada) is distinct from (old.batal_alasan, old.batal_oleh, old.batal_pada)
     and not (new.status = 'batal' and old.status <> 'batal') then
    raise exception 'Data pembatalan klaim EHC #% hanya diisi saat klaim dibatalkan.', old.id using errcode = '42501';
  end if;
  if new.transfer_batch_id is distinct from old.transfer_batch_id then
    if old.transfer_batch_id is null then
      if not (v_batch and new.status = 'disetujui') then
        raise exception 'Klaim EHC #% hanya masuk batch bila sudah disetujui GM, lewat rekap finance.', old.id
          using errcode = '42501';
      end if;
    elsif new.transfer_batch_id is null then
      if not (v_batch and old.ditransfer_pada is null and new.ditransfer_pada is null) then
        raise exception 'Klaim EHC #% hanya keluar dari batch lewat keluarkan_klaim_ehc_batch, sebelum referensi bank diisi.', old.id
          using errcode = '42501';
      end if;
    else
      raise exception 'Klaim EHC #% tidak bisa dipindah ke batch lain.', old.id using errcode = '42501';
    end if;
  end if;
  if new.ditransfer_pada is distinct from old.ditransfer_pada
     and not (old.ditransfer_pada is null and new.transfer_batch_id is not null and v_batch) then
    raise exception 'Tanda ditransfer klaim EHC #% hanya diisi otomatis saat referensi bank batch diisi.', old.id
      using errcode = '42501';
  end if;
  if old.status <> 'diajukan' and (to_jsonb(new) - v_bebas) is distinct from (to_jsonb(old) - v_bebas) then
    raise exception 'Klaim EHC #% sudah berstatus % — isinya tidak bisa diubah lagi.', old.id, old.status
      using errcode = '42501';
  end if;
  return new;
end $function$;
