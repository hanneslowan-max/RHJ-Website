CREATE OR REPLACE FUNCTION public.jaga_kolom_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r text; begin
  r := public.peran_saya();
  if r <> 'owner' then
    -- Satu pintu keluar: fungsi revisi_no_invoice() di bawah, yang menyimpan
    -- nomor lamanya lebih dulu. Pintu ini tidak bisa dibuka dari layar —
    -- set_config-nya hanya berlaku di dalam transaksi fungsi itu.
    if new.no_invoice is distinct from old.no_invoice
       and coalesce(current_setting('rhj.revisi', true), '') <> '1' then
      raise exception 'Nomor invoice tidak bisa diubah langsung. Pakai "Revisi nomor invoice" — nomor lamanya ikut disimpan.'
        using errcode = '42501';
    end if;
    if new.supplier      is distinct from old.supplier
    or new.tanggal_order is distinct from old.tanggal_order
    or new.mata_uang     is distinct from old.mata_uang
    or new.total_nilai   is distinct from old.total_nilai
    or new.kurs_estimasi is distinct from old.kurs_estimasi
    or new.nilai_estimasi is distinct from old.nilai_estimasi then
      raise exception 'Hanya owner yang boleh mengubah supplier, tanggal order, mata uang, nilai, atau kurs.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $function$;
