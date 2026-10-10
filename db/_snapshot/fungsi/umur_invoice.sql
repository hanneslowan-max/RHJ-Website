CREATE OR REPLACE FUNCTION public.umur_invoice(p_so bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when s.tgl_invoice is null then null
              when s.lunas and s.tgl_lunas is not null then (s.tgl_lunas - s.tgl_invoice)
              else (current_date - s.tgl_invoice) end
    from public.sales_orders s
   where s.id = p_so and public.boleh_lihat_sp(p_so)
$function$;
