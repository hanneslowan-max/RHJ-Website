-- ═══════════════════════════════════════════════════════════════════════
-- 136b · Review adversarial berkas 136 (temuan "fungsi", sedang): indeks product_id untuk view usulan_produk
--
-- Sesudah usulan_produk menjadi security_invoker (berkas 136), subquery per usulan (dipakai_po, dipakai_sp, customer,
-- qty_diminta, saringan opsi B) berjalan di bawah RLS po_baca/so_baca. po_lines, sales_order_lines, dan quote_lines
-- tidak punya indeks product_id → setiap usulan memindai seluruh baris PO/SP/penawaran sambil memanggil fungsi RLS
-- per baris. Uji DEV (rollback, 1.051 PO, 20 usulan): owner 2.486 ms → 19,5 ms, Iwan 3.980 ms → 23,7 ms. Tanpa
-- indeks, tab Menunggu Konfirmasi GM bisa kena batas waktu dan antrean usulan tampil kosong (layar kini menandai
-- "gagal dimuat", lihat index.html muatUsulan).
-- WAJIB ikut paket rilis PROD bersama berkas 136.
-- Hanya menambah indeks; tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

create index if not exists po_lines_product_idx        on public.po_lines (product_id);
create index if not exists sol_product_idx             on public.sales_order_lines (product_id);
create index if not exists quote_lines_product_idx     on public.quote_lines (product_id);

do $$ begin
  if to_regclass('public.po_lines_product_idx') is null
     or to_regclass('public.sol_product_idx') is null
     or to_regclass('public.quote_lines_product_idx') is null then
    raise exception '136b: indeks product_id belum terpasang';
  end if;
end $$;
