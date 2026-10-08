-- ═══════════════════════════════════════════════════════════════════════
-- 127 · #59 opsi B — usulan item dari PENAWARAN baru masuk antrean pengesahan setelah dipakai di PO/SP
--
-- Keputusan Hannes (7 Okt, opsi B): barang yang belum ada di master boleh diusulkan dari form penawaran (#59 inti,
-- usulkan_produk saat penawaran disimpan), tetapi usulan itu BARU tampil di antrean "Usulan item" (tab Menunggu
-- Konfirmasi GM) setelah benar-benar dipakai di PO atau SP. Penawaran yang tidak jadi order tidak membebani GM/staff.
--
-- Caranya: view usulan_produk menyembunyikan usulan yang HANYA dipakai di penawaran (ada di quote_lines, belum ada di
-- po_lines maupun sales_order_lines). Usulan dari PO/SP tampil seperti dulu; usulan yang belum dipakai di mana pun
-- (mis. simpan PO gagal sesudah usulkan_produk) juga tetap tampil seperti dulu. Begitu PO/SP memakai produk usulan
-- yang sama — usulkan_produk mengembalikan usulan yang sudah ada untuk teks yang sama (huruf besar/kecil diabaikan) —
-- ia muncul di antrean dengan hitungan PO/SP-nya.
--
-- Kolom, urutan kolom, penyaring akun_disetujui(), dan pemilik view TIDAK berubah (bukan security_invoker sejak
-- dulu — catatan keamanan terpisah: view ini membuka seluruh usulan & customer PO ke semua akun; dikerjakan di
-- tahap keamanan). Tidak ada data yang diubah. Tidak ada DROP.
--
-- Perbaikan hasil review (DEV: migrasi "127b_usulan_perbaikan"):
-- · dipakai_po / dipakai_sp / qty_diminta dihitung dengan subquery skalar — dulu LEFT JOIN po_lines × sales_order_lines
--   membuat qty_diminta berlipat (DEV: produk 812 terbaca 564, sebenarnya 282). Nama/tipe/urutan kolom tetap.
-- · usulkan_produk: sebelum membuat usulan baru, teks yang sama dengan produk yang SUDAH DISAHKAN (usulan_teks asal
--   atau kodenya) mengembalikan produk sah itu — dulu usulan yang disahkan di tengah jalan membuat simpan PO/SP gagal
--   products_kode_uniq berulang, atau melahirkan usulan dobel untuk SKU yang sudah sah. Produk sah yang dinonaktifkan
--   → ditolak dengan pesan jelas. Usulan dari penawaran kini dibuat di DALAM simpan_penawaran (berkas 129) sehingga
--   penawaran yang gagal disimpan tidak meninggalkan usulan yatim di antrean.
-- ═══════════════════════════════════════════════════════════════════════

create or replace view public.usulan_produk as
 select id, usulan_teks, kode, brand, satuan, dibuat_pada, dibuat_oleh, dipakai_po, dipakai_sp, customer, qty_diminta
   from ( select p.id,
                 p.usulan_teks,
                 p.kode,
                 p.brand,
                 p.satuan,
                 p.dibuat_pada,
                 p.dibuat_oleh,
                 (select count(distinct x.po_id) from po_lines x where x.product_id = p.id) as dipakai_po,
                 (select count(distinct s.so_id) from sales_order_lines s where s.product_id = p.id) as dipakai_sp,
                 ( select string_agg(distinct o.nama_customer, ', '::text) as string_agg
                     from po_lines x
                     join purchase_orders o on o.id = x.po_id
                    where x.product_id = p.id) as customer,
                 (select coalesce(sum(x.qty), 0::numeric) from po_lines x where x.product_id = p.id) as qty_diminta
            from products p
           where p.usulan
             -- #59 opsi B (berkas 127): usulan yang baru dipakai di penawaran menunggu sampai dipakai di PO/SP
             and (exists (select 1 from po_lines x2 where x2.product_id = p.id)
                  or exists (select 1 from sales_order_lines s2 where s2.product_id = p.id)
                  or not exists (select 1 from quote_lines q where q.product_id = p.id))) v
  where akun_disetujui();

-- usulkan_produk: teks yang sudah menjadi produk sah → produk sah itu (review #59 opsi B)
create or replace function public.usulkan_produk(p_teks text, p_brand text default null, p_satuan text default 'pcs')
returns bigint
language plpgsql
security definer
set search_path = public
as $function$
declare id_baru bigint; v_aktif boolean; v_kode text; t text := btrim(coalesce(p_teks, ''));
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

  -- #59 (berkas 127): teks yang sudah menjadi produk SAH (disahkan dari usulan dengan teks itu, atau kodenya sama)
  -- → produk sah itu, bukan usulan baru (dulu: gagal products_kode_uniq / usulan dobel untuk SKU yang sudah ada).
  select id, aktif, kode into id_baru, v_aktif, v_kode from public.products
   where not usulan
     and (lower(btrim(coalesce(usulan_teks, ''))) = lower(t) or lower(btrim(kode)) = lower(t))
   order by aktif desc, id
   limit 1;
  if id_baru is not null then
    if not coalesce(v_aktif, true) then
      raise exception 'Barang "%" sudah ada di master sebagai % tetapi dinonaktifkan — hubungi owner bila masih dipakai.', t, v_kode;
    end if;
    return id_baru;
  end if;

  insert into public.products (kode, brand, satuan, usulan, usulan_teks, aktif, dibuat_oleh)
  values (t, coalesce(nullif(btrim(coalesce(p_brand,'')), ''), '(usulan)'),
          coalesce(nullif(p_satuan,''), 'pcs'), true, t, true, auth.uid())
  returning id into id_baru;
  return id_baru;
end $function$;
