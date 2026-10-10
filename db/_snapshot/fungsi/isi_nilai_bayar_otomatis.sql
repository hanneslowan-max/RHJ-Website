CREATE OR REPLACE FUNCTION public.isi_nilai_bayar_otomatis()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.nilai_idr is null and new.jumlah_dibayar is not null and new.kurs_bayar is not null then
    new.nilai_idr := round(new.jumlah_dibayar * new.kurs_bayar, 2);
  end if;
  return new;
end $function$;
