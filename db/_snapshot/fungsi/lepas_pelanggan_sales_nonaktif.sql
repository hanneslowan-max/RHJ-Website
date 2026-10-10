CREATE OR REPLACE FUNCTION public.lepas_pelanggan_sales_nonaktif()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(old.aktif, true) and new.aktif = false then
    update public.customers
       set sales_rep_lama_id = sales_rep_id, sales_rep_id = null
     where sales_rep_id = new.id;
  end if;
  return new;
end $function$;
