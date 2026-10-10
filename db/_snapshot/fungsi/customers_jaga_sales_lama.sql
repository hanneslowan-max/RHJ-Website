CREATE OR REPLACE FUNCTION public.customers_jaga_sales_lama()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or public.peran_saya() in ('owner','gm','staff') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.sales_rep_lama_id := null;
  else
    new.sales_rep_lama_id := old.sales_rep_lama_id;
  end if;
  return new;
end $function$;
