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
                 count(distinct l.po_id) as dipakai_po,
                 count(distinct s.so_id) as dipakai_sp,
                 ( select string_agg(distinct o.nama_customer, ', '::text) as string_agg
                     from po_lines x
                     join purchase_orders o on o.id = x.po_id
                    where x.product_id = p.id) as customer,
                 coalesce(sum(l.qty), 0::numeric) as qty_diminta
            from products p
            left join po_lines l on l.product_id = p.id
            left join sales_order_lines s on s.product_id = p.id
           where p.usulan
             -- #59 opsi B (berkas 127): usulan yang baru dipakai di penawaran menunggu sampai dipakai di PO/SP
             and (exists (select 1 from po_lines x2 where x2.product_id = p.id)
                  or exists (select 1 from sales_order_lines s2 where s2.product_id = p.id)
                  or not exists (select 1 from quote_lines q where q.product_id = p.id))
           group by p.id) v
  where akun_disetujui();
