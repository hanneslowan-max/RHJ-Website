CREATE OR REPLACE FUNCTION public.sp_khusus_gm(p_rep bigint, p_customer bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.sales_reps r where r.id = p_rep and r.sp_hanya_gm)
      or exists (select 1 from public.customers c
                   join public.sales_reps r on r.id = c.sales_rep_id
                  where c.id = p_customer and r.sp_hanya_gm)
$function$;
