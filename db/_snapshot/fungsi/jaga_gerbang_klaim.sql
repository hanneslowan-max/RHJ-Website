CREATE OR REPLACE FUNCTION public.jaga_gerbang_klaim()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales_orders;
begin
  select * into s from public.sales_orders where id = new.so_id;
  if not found then raise exception 'Surat Pesanan tidak ditemukan.'; end if;
  new.sales_rep_id := coalesce(new.sales_rep_id, s.sales_rep_id);
  new.dibuat_oleh  := auth.uid();
  return new;
end $function$;
