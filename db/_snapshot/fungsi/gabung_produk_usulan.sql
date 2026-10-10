CREATE OR REPLACE FUNCTION public.gabung_produk_usulan(p_usulan bigint, p_tujuan bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.boleh_ubah_impor() then
    raise exception 'Hanya owner, GM, atau staff yang boleh menggabungkan produk.';
  end if;
  if p_usulan = p_tujuan then
    raise exception 'Produk tujuan tidak boleh sama dengan usulannya.';
  end if;
  if not exists (select 1 from public.products where id = p_usulan and usulan) then
    raise exception 'Yang digabungkan harus produk berstatus usulan.';
  end if;
  if not exists (select 1 from public.products where id = p_tujuan and not usulan) then
    raise exception 'Produk tujuan harus produk yang sudah sah, bukan usulan lain.';
  end if;

  update public.po_lines          set product_id = p_tujuan where product_id = p_usulan;
  update public.sales_order_lines set product_id = p_tujuan where product_id = p_usulan;
  update public.quote_lines       set product_id = p_tujuan where product_id = p_usulan;
  delete from public.products where id = p_usulan;
end $function$;
