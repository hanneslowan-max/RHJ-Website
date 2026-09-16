-- Berkas 59 (#2): izinkan pembuat PO (termasuk vonny) mengusulkan produk baru.
-- Sebelumnya digerbang boleh_alur_jual() (owner/gm/staff/sales, TANPA vonny), sehingga
-- submit PO oleh vonny dengan item baru gagal ("Peran Anda tidak boleh mengusulkan produk baru.").
-- boleh_input_po() = owner/gm/staff/sales/vonny = superset yang tepat (para pembuat PO).
-- CREATE OR REPLACE mempertahankan ACL — tidak menambah akses anon.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 14 Sep 2026. Belum ke produksi (prod masih pre-berkas-52).

CREATE OR REPLACE FUNCTION public.usulkan_produk(p_teks text, p_brand text DEFAULT NULL::text, p_satuan text DEFAULT 'pcs'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare id_baru bigint; t text := btrim(coalesce(p_teks, ''));
begin
  if not public.boleh_input_po() then
    raise exception 'Peran Anda tidak boleh mengusulkan produk baru.';
  end if;
  if t = '' then
    raise exception 'Nama barangnya belum diisi.';
  end if;

  -- Usulan yang sama persis tidak digandakan.
  select id into id_baru from public.products
   where usulan and lower(btrim(coalesce(usulan_teks, kode))) = lower(t)
   limit 1;
  if id_baru is not null then return id_baru; end if;

  insert into public.products (kode, brand, satuan, usulan, usulan_teks, aktif, dibuat_oleh)
  values (t, coalesce(nullif(btrim(coalesce(p_brand,'')), ''), '(usulan)'),
          coalesce(nullif(p_satuan,''), 'pcs'), true, t, true, auth.uid())
  returning id into id_baru;
  return id_baru;
end $function$;
