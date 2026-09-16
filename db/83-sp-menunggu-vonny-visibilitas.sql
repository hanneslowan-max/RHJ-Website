-- Berkas 83 (revisi visibilitas berkas 82): SP yang SEDANG dicek Vonny hanya boleh dilihat oleh
--   owner, GM, Vonny, dan SALES pemiliknya. Peran lain (staff/finance/liesian/ichi/lenni) TIDAK bisa
--   melihat sampai Vonny approve. Sesudah vonny_ok / ada surat jalan / batal → visibilitas normal.
-- "sedang dicek Vonny" = NOT batal AND no_surat_jalan IS NULL AND coalesce(vonny_ok,false)=false.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

alter policy so_baca on public.sales_orders using (
  ( public.peran_saya() = 'sales' and sales_rep_id = public.sales_rep_saya() )
  or case
       when (not batal and no_surat_jalan is null and coalesce(vonny_ok, false) = false)
         then public.peran_saya() in ('owner','gm','vonny')
         else public.boleh_lihat_semua_jual()
     end
);
