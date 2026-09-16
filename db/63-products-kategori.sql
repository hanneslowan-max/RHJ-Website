-- Berkas 63 (#26): kolom kategori produk + backfill dari kelompok.
-- FE (index.html): field "Kategori produk" (select) di formProduk + disimpan di simpanProduk.
-- Produk dimuat via select=* jadi kolom baru otomatis ikut.
-- Backfill kasar dari kelompok (Roda default; Pallet Mesh / Hand Pallet / Hospital / Lainnya bila cocok) — bisa dikoreksi manual.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS kategori text;

UPDATE public.products SET kategori = CASE
  WHEN kelompok ILIKE '%pallet mesh%' THEN 'Pallet Mesh'
  WHEN kelompok ILIKE '%hand pallet%' THEN 'Hand Pallet'
  WHEN kelompok ILIKE '%hospital bed%' OR kelompok ILIKE '%bed equipment%' THEN 'Hospital'
  WHEN kelompok ILIKE '%actuator%' THEN 'Lainnya'
  ELSE 'Roda'
END
WHERE kategori IS NULL;
