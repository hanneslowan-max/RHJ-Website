CREATE OR REPLACE FUNCTION public.pic_pelanggan_saya(p_customer bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.peran_saya() <> 'sales'
      or exists (select 1 from public.customers c
                  where c.id = p_customer
                    and (c.sales_rep_id is null
                         or c.sales_rep_id = public.sales_rep_saya()))
$function$;
