CREATE OR REPLACE FUNCTION public.orders_nomor_ubah_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Perubahan yang datang DARI hitung_ulang_status sendiri tidak boleh
  -- memanggilnya lagi; tanpa ini triggernya memanggil dirinya tanpa henti.
  if coalesce(current_setting('rhj.alur', true), '') = '1' then return new; end if;
  if new.no_proforma is distinct from old.no_proforma
  or new.no_do       is distinct from old.no_do then
    perform public.hitung_ulang_status(new.id);
  end if;
  return new;
end $function$;
