-- 116: percepat RLS — fungsi peran dievaluasi SEKALI per query, bukan per baris.
--
-- Masalah: tab Pelanggan kena "canceling statement due to statement timeout" saat banyak
-- orang membukanya bersamaan. Policy cust_baca memanggil boleh_baca(), peran_saya(),
-- sales_rep_saya() langsung. Ketiganya SECURITY DEFINER sehingga tidak di-inline dan
-- dipanggil untuk SETIAP baris (5.398 pelanggan × 3 fungsi × tiap fungsi query profiles).
-- Satu count(*) sebagai sales = ±830 ms; tab Pelanggan menembak 5 query sekaligus (daftar +
-- 4 hitungan) → ±4 detik CPU per pembukaan tab. Beberapa orang serentak → lewat batas 8 detik.
--
-- Perbaikan: bungkus pemanggilan dengan (select fungsi()) → Postgres menjadikannya InitPlan
-- yang dihitung sekali per query. Logika & hasil TIDAK berubah (diuji: jumlah baris sama).
-- Diukur di DEV: count(*) sebagai sales 832 ms → 3 ms.

alter policy cust_baca on public.customers
  using ((select boleh_baca())
         and (((select peran_saya()) <> 'sales') or sales_rep_id is null
              or sales_rep_id = (select sales_rep_saya())));

alter policy cust_ubah on public.customers
  using ((select boleh_ubah_crm())
         and (((select peran_saya()) <> 'sales') or sales_rep_id is null
              or sales_rep_id = (select sales_rep_saya())))
  with check ((select boleh_ubah_crm())
         and (((select peran_saya()) <> 'sales') or sales_rep_id is null
              or sales_rep_id = (select sales_rep_saya())));

alter policy lead_baca on public.leads
  using ((select boleh_lihat_semua_lead())
         or ((select peran_saya()) = 'sales' and sales_rep_id = (select sales_rep_saya())));

alter policy harga_baca on public.price_list using ((select boleh_lihat_harga()));

alter policy produk_baca on public.products using ((select boleh_lihat_produk()));

alter policy tsr_baca on public.tautan_sales_baris
  using ((select peran_saya()) = any (array['owner','gm','staff']));

-- 116b: urutan default tab Pelanggan = urut_sumber, nama_urut, id. Indeks lama
-- customers_urut_idx masih (urut_sumber, nama, id) sehingga tetap perlu sortir ulang.
create index if not exists customers_urut_nama_urut_idx on public.customers (urut_sumber, nama_urut, id);
