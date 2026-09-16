-- Berkas 84: cabut EXECUTE dari public/anon pada fungsi TRIGGER baru sesi ini
--   (po_auto_klaim_sales — berkas 79; jaga_kirim_bertahap — berkas 76).
-- Keduanya RETURNS trigger → dijalankan sistem trigger, bukan lewat grant, jadi revoke tak
--   memengaruhi trigger; hanya menutup jalur RPC teoretis (Supabase linter 0028), konsisten berkas 75.
-- Diverifikasi: has_function_privilege('anon',...,'execute') = false utk keduanya.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.
revoke execute on function public.po_auto_klaim_sales() from public, anon;
revoke execute on function public.jaga_kirim_bertahap() from public, anon;
