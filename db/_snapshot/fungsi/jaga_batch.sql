CREATE OR REPLACE FUNCTION public.jaga_batch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.dibuat_oleh is distinct from old.dibuat_oleh
  or new.dibuat_pada is distinct from old.dibuat_pada
  or new.periode_bayar is distinct from old.periode_bayar then
    raise exception 'Batch transfer #%: pembuat, waktu dibuat, dan periode bayar tidak bisa diubah.', old.id
      using errcode = '42501';
  end if;
  if new.no_referensi is distinct from old.no_referensi and btrim(new.no_referensi) = '' then
    raise exception 'Nomor referensi batch #% tidak boleh kosong.', old.id using errcode = '22023';
  end if;
  if old.no_referensi is not null then
    if new.no_referensi is null then
      raise exception 'Batch transfer #% sudah berreferensi bank — referensinya tidak bisa dikosongkan.', old.id
        using errcode = '42501';
    end if;
    if new.jumlah_klaim is distinct from old.jumlah_klaim or new.total is distinct from old.total then
      raise exception 'Batch transfer #% sudah berreferensi bank — isinya beku.', old.id using errcode = '42501';
    end if;
  end if;
  if new.no_referensi is distinct from old.no_referensi then
    new.ref_oleh := auth.uid();
    new.ref_pada := now();
  else
    new.ref_oleh := old.ref_oleh;
    new.ref_pada := old.ref_pada;
  end if;
  if coalesce(current_setting('rhj.batch', true), '') = 'on' then
    return new;
  end if;
  if new.jenis        is distinct from old.jenis
  or new.bulan        is distinct from old.bulan
  or new.tanggal      is distinct from old.tanggal
  or new.jumlah_klaim is distinct from old.jumlah_klaim
  or new.total        is distinct from old.total
  or new.cepat        is distinct from old.cepat then
    raise exception
      'Batch transfer #% tidak bisa diubah isinya. Yang masih boleh diisi cuma nomor '
      'referensi bank dan catatan. Angka dan tanggalnya adalah cap waktu — begitu bisa '
      'diedit, ia berhenti jadi bukti.', old.id;
  end if;
  return new;
end $function$;
