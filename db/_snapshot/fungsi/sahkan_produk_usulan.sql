CREATE OR REPLACE FUNCTION public.sahkan_produk_usulan(p_id bigint, p_kode text, p_brand text, p_kelompok text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.boleh_ubah_impor() then
    raise exception 'Hanya owner, GM, atau staff yang boleh mengesahkan produk.';
  end if;
  if coalesce(btrim(p_kode),'') = '' or coalesce(btrim(p_brand),'') = '' then
    raise exception 'Kode internal dan brand wajib diisi saat mengesahkan.';
  end if;
  if not exists (select 1 from public.products where id = p_id and usulan) then
    raise exception 'Produk itu bukan usulan, atau sudah pernah disahkan.';
  end if;
  update public.products
     set kode = btrim(p_kode), brand = btrim(p_brand),
         kelompok = nullif(btrim(coalesce(p_kelompok,'')), ''),
         usulan = false, diubah_oleh = auth.uid(), diubah_pada = now()
   where id = p_id;
end $function$;
