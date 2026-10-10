CREATE OR REPLACE FUNCTION public.jaga_harga_usulan()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare u boolean;
begin
  select usulan into u from public.products where id = new.product_id;
  if coalesce(u, false) then
    raise exception 'Produk ini masih berstatus usulan. Sahkan dulu di antrean '
                    'usulan produk — beri kode internal dan brand — baru harganya '
                    'bisa dimasukkan. Selama belum disahkan, komisinya memang '
                    'sengaja tidak bisa dihitung.';
  end if;
  return new;
end $function$;
