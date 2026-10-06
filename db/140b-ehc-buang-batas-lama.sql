-- DRAF — BELUM dijalankan. Jangan dijalankan.
-- ═══════════════════════════════════════════════════════════════════════
-- 140b · EHC tahap 1 — buang dua batas lama (DIJALANKAN MANUAL di SQL Editor)
--
-- Pasangan berkas 140. Isinya hanya DROP, yang tidak bisa dijalankan lewat
-- MCP Supabase (perintah DROP macet menunggu konfirmasi yang tidak muncul).
-- Jalankan SESUDAH 140, SEBELUM index.html baru dipakai.
--
--   1 · ehck_so_uniq — indeks unik "satu SP satu klaim EHC". Diganti model
--       saldo: satu SP boleh dipakai banyak klaim sampai saldonya habis
--       (dijaga simpan_klaim_ehc + penjaga saldo berkas 140).
--   2 · ehck_cara_bayar_sah — CHECK lama (transfer|tunai). Penggantinya
--       ehck_cara_bayar_sah2 (transfer|tunai|reimburse|kartu_kredit) sudah
--       dipasang di 140.
--
-- Tidak ada data yang diubah.
-- ═══════════════════════════════════════════════════════════════════════
drop index if exists public.ehck_so_uniq;
alter table public.ehc_klaim drop constraint if exists ehck_cara_bayar_sah;
