CREATE OR REPLACE FUNCTION public.segarkan_status_sp_harga()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v bigint; p bigint;
begin
  p := coalesce(new.product_id, old.product_id);
  if p is null then return null; end if;
  perform set_config('rhj.hitung_status', 'on', true);
  for v in select distinct l.so_id
             from public.sales_order_lines l
             join public.sales_orders s on s.id = l.so_id
            where l.product_id = p and not s.batal and not s.lunas loop
    update public.sales_orders set status = public.status_sp_hitung(v)
     where id = v and status is distinct from public.status_sp_hitung(v);
  end loop;
  perform set_config('rhj.hitung_status', 'off', true);
  return null;
end $function$;
