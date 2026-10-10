CREATE OR REPLACE FUNCTION public.isi_kolom_jejak()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if TG_OP = 'INSERT' then
    new.dibuat_oleh := auth.uid(); new.dibuat_pada := now();
  end if;
  new.diubah_oleh := auth.uid(); new.diubah_pada := now();
  return new;
end $function$;
