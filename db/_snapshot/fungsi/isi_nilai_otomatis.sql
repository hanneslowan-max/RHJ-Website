CREATE OR REPLACE FUNCTION public.isi_nilai_otomatis()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  -- nilai_estimasi terisi sendiri kalau dibiarkan kosong; kalau diketik, dihormati
  if new.nilai_estimasi is null and new.total_nilai is not null and new.kurs_estimasi is not null then
    new.nilai_estimasi := round(new.total_nilai * new.kurs_estimasi, 2);
  end if;
  return new;
end $function$;
