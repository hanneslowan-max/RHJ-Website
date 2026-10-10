CREATE OR REPLACE FUNCTION public.sales_id_dari_nama(p_nama text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when count(*) = 1 then min(r.id) end
    from public.sales_reps r
   where public.norm_sales(r.nama) = public.norm_sales(p_nama)
$function$;
