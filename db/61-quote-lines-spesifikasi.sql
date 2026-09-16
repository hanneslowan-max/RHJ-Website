-- Berkas 61 (#3): kolom spesifikasi per-baris di penawaran (quote_lines).
-- Additive & aman (nullable, tanpa default). Notes header memakai quotes.catatan (sudah ada).
-- FE (index.html): input .pnw-spek per baris di pnwBarisHtml + listener di pasangPenawaran +
--   ikut dikirim saat POST /quote_lines (spesifikasi: b.spesifikasi || null).
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

ALTER TABLE public.quote_lines ADD COLUMN IF NOT EXISTS spesifikasi text;
