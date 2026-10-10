CREATE OR REPLACE FUNCTION public.akun_sales_saya()
 RETURNS TABLE(sales_rep_id bigint, sales_nama text, peran text, tertaut boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id, r.nama, public.peran_saya(), r.id is not null
    from (select 1) x
    left join public.sales_reps r on r.profile_id = auth.uid()
$function$;
