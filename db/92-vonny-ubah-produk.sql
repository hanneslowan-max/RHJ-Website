-- Berkas 92 (#27): Vonny boleh MEMBUAT & MENGUBAH master produk; order impor tetap baca saja.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026. Belum ke produksi.
--
-- Keputusan Hannes (#27): Vonny boleh membuat & mengubah produk (products), TIDAK boleh mengubah
-- order impor (orders, import_lines, payments tetap tertutup untuk ditulis; order cukup dilihat),
-- menghapus produk tetap owner saja.
--
-- Kenapa TIDAK mengubah boleh_ubah_impor() (owner, gm, staff): fungsi itu juga menjaga
--   factory_codes, product_sets, product_set_components, boleh_massal (ubah massal kolom produk),
--   sahkan_produk_usulan, gabung_produk_usulan, dan jaga_kolom_sales bagian g (ganti sales pemilik
--   SP). Memasukkan Vonny ke sana ikut membuka semua itu. Order impor sendiri memakai
--   boleh_alur_impor (order_ubah, baris_*), setara_owner (order_tambah), boleh_ubah_bayar (bayar_*)
--   — tidak disentuh.
--
-- Kolom sensitif di products: tidak ada harga beli / HPP / pabrik (HPP di product_costs, kode
--   pabrik di factory_codes — keduanya tidak dibuka). Vonny sudah bisa MEMBACA seluruh products
--   (produk_baca = boleh_lihat_produk → boleh_lihat_harga, termasuk vonny).
--
-- Isi berkas:
--   (1) boleh_ubah_produk() = boleh_ubah_impor() OR peran vonny.
--   (2) RLS products: produk_tambah & produk_ubah → boleh_ubah_produk(). produk_hapus TETAP
--       boleh_hapus() (owner).
--   (3) RLS suppliers: sup_baca → boleh_lihat_order_impor() (= boleh_lihat_impor + vonny), supaya
--       layar order/produk Vonny tidak kosong nama pabriknya. sup_tambah/sup_ganti tetap
--       setara_owner, sup_hapus tetap owner. payments (bayar_baca = boleh_lihat_impor) TETAP tertutup.
--   (4) Penjaga kolom (trigger products_jaga_kolom, BEFORE UPDATE): RLS membuka SELURUH kolom
--       products untuk Vonny, padahal status usulan adalah gerbang owner/GM/staff
--       (sahkan_produk_usulan / gabung_produk_usulan). Tanpa penjaga, PATCH usulan=false melangkahi
--       antrean usulan. Selain owner/GM/staff: usulan, usulan_teks, id_lama, dibuat_oleh,
--       dibuat_pada tidak boleh diubah. auth.uid() null (migrasi / service role) tidak dijaga.
--       INSERT tidak dijaga: usulkan_produk (sales/Vonny) memang INSERT usulan=true.
--
-- Sengaja TIDAK diubah: storage dokumen_baca (unduh dokumen order impor tetap boleh_lihat_impor —
--   "order cukup dilihat"; tombol Unduh disembunyikan di FE untuk Vonny). Policy siap pakai bila
--   Hannes kelak ingin Vonny bisa mengunduh (JANGAN diterapkan tanpa persetujuan):
--     create policy rhj_dokumen_impor_vonny on storage.objects for select to authenticated
--       using (bucket_id = 'dokumen' and public.peran_saya() = 'vonny'
--              and exists (select 1 from public.documents d where d.path = objects.name));
--
-- Membalik: alter policy produk_tambah/produk_ubah kembali ke boleh_ubah_impor(); sup_baca kembali
--   ke boleh_lihat_impor(); drop trigger products_jaga_kolom; drop function jaga_kolom_produk(),
--   boleh_ubah_produk().

-- (1)
create or replace function public.boleh_ubah_produk()
returns boolean
language sql
stable security definer
set search_path = public
as $$
  -- #27: buat & ubah master produk. Hapus tetap boleh_hapus(); ubah massal, kode pabrik, set roda,
  -- sahkan/gabung usulan tetap boleh_ubah_impor().
  select public.boleh_ubah_impor() or public.peran_saya() = 'vonny'
$$;
revoke execute on function public.boleh_ubah_produk() from public, anon;
grant  execute on function public.boleh_ubah_produk() to authenticated;

-- (2)
alter policy produk_tambah on public.products
  with check (public.boleh_ubah_produk());
alter policy produk_ubah on public.products
  using (public.boleh_ubah_produk())
  with check (public.boleh_ubah_produk());

-- (3)
alter policy sup_baca on public.suppliers
  using (public.boleh_lihat_order_impor());

-- (4)
create or replace function public.jaga_kolom_produk()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.boleh_ubah_impor() then
    if new.usulan      is distinct from old.usulan
       or new.usulan_teks is distinct from old.usulan_teks
       or new.id_lama     is distinct from old.id_lama
       or new.dibuat_oleh is distinct from old.dibuat_oleh
       or new.dibuat_pada is distinct from old.dibuat_pada then
      raise exception 'Peran Anda (%) boleh mengubah produk, tapi tidak status usulan, teks usulan, id lama, atau jejak pembuatnya. Mengesahkan usulan: owner, GM, atau staff lewat "Sahkan".',
        public.peran_saya() using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.jaga_kolom_produk() from public, anon;

drop trigger if exists products_jaga_kolom on public.products;
create trigger products_jaga_kolom
  before update on public.products
  for each row execute function public.jaga_kolom_produk();
