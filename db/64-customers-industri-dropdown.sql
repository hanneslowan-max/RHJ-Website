-- Berkas 64 (#25): "industri" jadi kategori dropdown 3 opsi (Otomotif / Non Otomotif / Bengkel Otomotif).
-- Data lama dikosongkan sesuai keputusan Hannes, TAPI dipindah dulu ke industri_lama supaya reversibel.
-- Pengisian ulang dilakukan Vonny saat cek SP (#8) bila customer belum berkategori.
-- FE (index.html): field plc_industri diubah dari teks bebas menjadi select 3 opsi.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS industri_lama text;
UPDATE public.customers SET industri_lama = industri WHERE industri IS NOT NULL AND industri_lama IS NULL;
UPDATE public.customers SET industri = NULL WHERE industri IS NOT NULL;
