CREATE OR REPLACE FUNCTION public.hitung_ulang_status_sp(p_so bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.sales_orders set status = public.status_sp_hitung(p_so) where id = p_so;
end $function$;
