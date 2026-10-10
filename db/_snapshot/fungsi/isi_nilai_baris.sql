CREATE OR REPLACE FUNCTION public.isi_nilai_baris()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.nilai is null then new.nilai := round(new.qty * new.harga_satuan, 2); end if;
  -- product_id ikut kode pabriknya kalau tidak diisi
  if new.product_id is null and new.factory_code_id is not null then
    select product_id into new.product_id from public.factory_codes where id = new.factory_code_id;
  end if;
  return new;
end $function$;
