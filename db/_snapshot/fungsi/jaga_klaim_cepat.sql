CREATE OR REPLACE FUNCTION public.jaga_klaim_cepat()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.cepat_minta       is not distinct from old.cepat_minta
 and new.cepat_ok          is not distinct from old.cepat_ok
 and new.cepat_alasan      is not distinct from old.cepat_alasan
 and new.cepat_catatan     is not distinct from old.cepat_catatan
 and new.cepat_diminta_oleh is not distinct from old.cepat_diminta_oleh
 and new.cepat_diminta_pada is not distinct from old.cepat_diminta_pada
 and new.cepat_diputus_oleh is not distinct from old.cepat_diputus_oleh
 and new.cepat_diputus_pada is not distinct from old.cepat_diputus_pada then
    return new;
  end if;
  if coalesce(current_setting('rhj.cepat', true), '') <> 'on' then
    raise exception
      'Keadaan "klaim cepat" tidak bisa diubah langsung. Pakai minta_klaim_cepat(), '
      'batalkan_klaim_cepat(), atau putuskan_klaim_cepat() — kalau tidak, permintaan '
      'dan putusan GM bisa berubah tanpa satu pun baris di riwayatnya.'
      using errcode = '42501';
  end if;
  -- Sesudah uangnya keluar, permintaannya adalah catatan sejarah.
  if old.transfer_batch_id is not null then
    raise exception
      'Klaim EHC ini sudah masuk batch transfer #%. Keadaan "klaim cepat"-nya tidak bisa '
      'diubah lagi — ia sudah jadi bagian dari bukti pembayaran itu.', old.transfer_batch_id
      using errcode = '42501';
  end if;
  return new;
end $function$;
