CREATE OR REPLACE FUNCTION public.quotes_wajib_baris()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return null; end if;   -- migrasi / service role
  if exists (select 1 from public.quotes q where q.id = new.id)
     and not exists (select 1 from public.quote_lines l where l.quote_id = new.id) then
    raise exception 'Penawaran tanpa baris tidak disimpan — pakai tombol Simpan penawaran.';
  end if;
  return null;
end $function$;
