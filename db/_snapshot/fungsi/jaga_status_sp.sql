CREATE OR REPLACE FUNCTION public.jaga_status_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status is distinct from old.status then
    if coalesce(current_setting('rhj.hitung_status', true), 'off') = 'on' then
      return new;                                   -- datang dari fungsi hitung
    end if;
    raise exception 'Status SP dihitung dari dokumennya, tidak boleh diketik. '
                    'Isi surat jalan / invoice / pelunasan untuk memindahkannya.';
  end if;
  new.diubah_pada := now();
  new.diubah_oleh := auth.uid();
  return new;
end $function$;
