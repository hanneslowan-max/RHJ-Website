-- ═══════════════════════════════════════════════════════════════════════
-- 136 · Temuan keamanan #3 (keputusan Hannes 9 Okt, no. 11): view usulan_produk ikut hak baca pembacanya
--
-- Celah: view usulan_produk milik postgres TANPA security_invoker → berjalan dengan hak pemiliknya dan melompati RLS
-- po_lines/purchase_orders (sales hanya miliknya), sales_order_lines/sales_orders (aturan SP menunggu Vonny, berkas 83)
-- dan quote_lines. Saringannya hanya akun_disetujui(), jadi setiap akun yang disetujui (termasuk sales, Lie Sian,
-- selfie) membaca customer PO, qty, dan jumlah PO/SP milik sales lain (uji DEV: Iwan membaca customer & qty PO
-- Hendri/Alfred yang langsung dari purchase_orders 0 baris). Hak bawaan Supabase juga memberi anon & authenticated
-- hak penuh atas view (anon tertahan hanya karena EXECUTE akun_disetujui sudah dicabut).
--
-- Perbaikan:
--  · View dibuat ulang dengan security_invoker = on — isi, kolom, urutan, tipe, dan saringan opsi B (berkas 127)
--    sama persis; customer/qty/hitungan PO/SP dihitung dari dokumen yang BOLEH dibaca pembacanya.
--  · Baris yang tampil: owner/GM/staff (boleh_ubah_impor) = antrean pengesahan penuh; peran lain hanya usulan yang ia
--    buat sendiri atau yang dipakai di PO/SP yang boleh ia lihat. Lie Sian / selfie / pending: kosong.
--  · Hak: anon tidak punya hak apa pun; authenticated hanya SELECT.
-- Perilaku yang diketahui (tidak bocor, dicatat di HANDOFF):
--  · Staff mengikuti aturan baca SP berkas 83 (keputusan Hannes 9 Okt no. 11): usulan yang dipakai di penawaran DAN di
--    SP 'menunggu vonny' milik orang lain baru tampil untuk staff sesudah dicek Vonny; usulan yang HANYA dipakai di SP
--    seperti itu tampil untuk staff dengan Dipakai SP 0 & Customer '—' (tetap bisa disahkan). Owner/GM selalu lengkap.
--  · Usulan buatan sales X yang hanya dipakai di penawaran sales lain tampil di antrean X dengan 0/0 (owner/GM tidak
--    melihatnya — opsi B); usulan X yang ada di penawarannya dan dipakai di PO sales lain tidak tampil bagi X. Yang
--    terlihat X hanya teks usulannya sendiri, yang memang terbaca semua sales lewat /products (#59, disengaja).
-- PERINGATAN: setiap "create or replace view usulan_produk" berikutnya WAJIB membawa "with (security_invoker = on)" —
-- tanpa klausa itu PostgreSQL mengosongkan opsinya (terbukti di DEV) dan kebocorannya kembali. Jangan menutup kolom
-- products.dibuat_oleh dengan revoke kolom (mematahkan /products?select=* dan view ini).
-- Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

create or replace view public.usulan_produk with (security_invoker = on) as
 select id, usulan_teks, kode, brand, satuan, dibuat_pada, dibuat_oleh, dipakai_po, dipakai_sp, customer, qty_diminta
   from ( select p.id,
                 p.usulan_teks,
                 p.kode,
                 p.brand,
                 p.satuan,
                 p.dibuat_pada,
                 p.dibuat_oleh,
                 (select count(distinct x.po_id) from public.po_lines x where x.product_id = p.id) as dipakai_po,
                 (select count(distinct s.so_id) from public.sales_order_lines s where s.product_id = p.id) as dipakai_sp,
                 ( select string_agg(distinct o.nama_customer, ', '::text) as string_agg
                     from public.po_lines x
                     join public.purchase_orders o on o.id = x.po_id
                    where x.product_id = p.id) as customer,
                 (select coalesce(sum(x.qty), 0::numeric) from public.po_lines x where x.product_id = p.id) as qty_diminta
            from public.products p
           where p.usulan
             -- #59 opsi B (berkas 127): usulan yang baru dipakai di penawaran menunggu sampai dipakai di PO/SP
             and (exists (select 1 from public.po_lines x2 where x2.product_id = p.id)
                  or exists (select 1 from public.sales_order_lines s2 where s2.product_id = p.id)
                  or not exists (select 1 from public.quote_lines q where q.product_id = p.id))) v
  where (select public.akun_disetujui())
    and ((select public.boleh_ubah_impor())        -- owner/GM/staff: antrean pengesahan, termasuk usulan yatim
         or v.dibuat_oleh = (select auth.uid())    -- usulan yang ia buat sendiri
         or v.dipakai_po > 0                       -- dipakai di PO yang boleh ia lihat (RLS po_baca)
         or v.dipakai_sp > 0);                     -- dipakai di SP yang boleh ia lihat (RLS so_baca)

revoke all on public.usulan_produk from public, anon, authenticated;
grant select on public.usulan_produk to authenticated;

do $$
begin
  if not exists (select 1 from pg_class
                  where oid = 'public.usulan_produk'::regclass
                    and coalesce(reloptions::text[] @> array['security_invoker=on'], false)) then
    raise exception '136: view usulan_produk harus security_invoker';
  end if;
  if has_table_privilege('anon', 'public.usulan_produk', 'select')
     or has_table_privilege('authenticated', 'public.usulan_produk', 'insert') then
    raise exception '136: hak usulan_produk belum dipersempit';
  end if;
end $$;
