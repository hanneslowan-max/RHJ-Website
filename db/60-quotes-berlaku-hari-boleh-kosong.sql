-- Berkas 60 (#5): masa berlaku penawaran boleh kosong (tanpa batas), tidak lagi auto-14.
-- Baris lama tetap menyimpan nilainya; hanya baris baru boleh NULL.
-- FE (index.html): pnwFormBaru berlaku_hari:"" ; simpanPenawaran kirim null bila kosong ;
--   tampilan menandai null sebagai "tanpa batas" (tidak dihitung kedaluwarsa).
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 14 Sep 2026. Belum ke produksi.

ALTER TABLE public.quotes
  ALTER COLUMN berlaku_hari DROP DEFAULT,
  ALTER COLUMN berlaku_hari DROP NOT NULL;
