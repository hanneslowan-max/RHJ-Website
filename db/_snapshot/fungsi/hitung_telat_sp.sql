CREATE OR REPLACE FUNCTION public.hitung_telat_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.telat := coalesce(new.lunas, false)
           and new.tgl_lunas   is not null
           and new.tgl_invoice is not null
           and (new.tgl_lunas - new.tgl_invoice) > 120;
  return new;
end $function$;
