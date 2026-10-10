CREATE OR REPLACE FUNCTION public.jaga_riwayat_tetap()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  raise exception 'Riwayat tidak bisa diubah (%).', tg_table_name using errcode = '42501';
end $function$;
