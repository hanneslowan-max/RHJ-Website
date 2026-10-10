CREATE OR REPLACE FUNCTION public.customers_sales_bawaan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' and public.peran_saya() = 'sales' then
    if new.sales_rep_id is not null and new.sales_rep_id is distinct from public.sales_rep_saya() then
      raise exception 'Sales hanya bisa menambah pelanggan untuk dirinya sendiri — pelanggan baru yang Anda tambahkan '
                      'otomatis menjadi milik Anda. Pemindahan ke sales lain diputuskan owner, GM, atau staff.'
        using errcode = 'P0001';
    end if;
    new.sales_rep_id := public.sales_rep_saya();
  end if;
  return new;
end $function$;
