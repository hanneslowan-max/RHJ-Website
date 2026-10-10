CREATE OR REPLACE FUNCTION public.jaga_nilai_terkunci()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_batch bigint; v_jenis text; v_kode text; v_peng bigint;
begin
  if TG_TABLE_NAME = 'ehc_klaim_nilai' then
    select transfer_batch_id into v_batch from public.ehc_klaim where id = new.klaim_id;
    v_jenis := 'EHC'; v_kode := 'ehc';
    if (new.nominal is distinct from old.nominal or new.kas is distinct from old.kas)
       and exists (select 1 from public.ehc_klaim k where k.id = new.klaim_id and k.status <> 'diajukan') then
      raise exception 'Nominal klaim EHC ini sudah diputus GM (berkas 141) — tidak bisa diubah lagi.' using errcode = '42501';
    end if;
  else
    select transfer_batch_id into v_batch from public.komisi_klaim where id = new.klaim_id;
    v_jenis := 'komisi'; v_kode := 'komisi';
  end if;

  if v_batch is not null then
    raise exception
      'Nominal klaim % ini sudah masuk batch transfer #%. Nominalnya tidak bisa diubah lagi — '
      'kalau boleh, total yang tercatat di batch tidak lagi cocok dengan isinya, dan yang satu '
      'berhenti membuktikan yang lain. Kalau memang ada yang salah, buat koreksi terpisah.',
      v_jenis, v_batch;
  end if;

  -- Kunci kedua: GM sudah MELIHAT angka ini di pengajuan yang masih hidup.
  v_peng := public.klaim_terkunci_pengajuan(v_kode, new.klaim_id);
  if v_peng is not null and new.nominal is distinct from old.nominal then
    raise exception
      'Nominal klaim % ini sudah masuk pengajuan transfer #% yang belum selesai, jadi GM sudah '
      'melihat angkanya. Mengubahnya sekarang berarti yang disetujui dan yang dibayar bukan '
      'angka yang sama. Kalau memang salah, tarik dulu pengajuannya '
      '(tarik_pengajuan_transfer), perbaiki nominalnya, lalu ajukan lagi.',
      v_jenis, v_peng
      using errcode = '42501';
  end if;

  return new;
end $function$;
