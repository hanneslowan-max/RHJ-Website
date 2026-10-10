CREATE OR REPLACE FUNCTION public.jaga_status_otomatis()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(current_setting('rhj.alur', true), '') = '1' then
    return new;                                   -- perubahan dari alur, boleh
  end if;
  if new.status_produksi is distinct from old.status_produksi
  or new.status_dokumen  is distinct from old.status_dokumen then
    raise exception 'Status produksi dan status dokumen tidak bisa diubah manual. Keduanya mengikuti dokumen yang diunggah.'
      using errcode = '42501';
  end if;
  return new;
end $function$;
