CREATE OR REPLACE FUNCTION public.jaga_saldo_ehc_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if TG_TABLE_NAME = 'sales_order_lines' then
    if TG_OP in ('UPDATE','DELETE') then perform public.periksa_saldo_ehc_sp(old.so_id); end if;
    if TG_OP = 'INSERT' or (TG_OP = 'UPDATE' and new.so_id is distinct from old.so_id) then
      perform public.periksa_saldo_ehc_sp(new.so_id);
    end if;
  else
    perform public.periksa_saldo_ehc_sp(new.id);
  end if;
  return null;
end $function$;
