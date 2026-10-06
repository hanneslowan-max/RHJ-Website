-- ═══════════════════════════════════════════════════════════════════════
-- 118 · Sales "Ahen" (id 1) diganti nama jadi "Hendri"
--
-- Keputusan Hannes (2026-10-06): "semua yang atas nama Ahen dipindahkan ke Hendri".
-- Akun login sales id 1 memang milik Hendri Pratomo, dan ke-432 pelanggannya berasal
-- dari Hendri (berkas 117). Jadi yang diganti NAMA-nya, datanya tidak dipindah: login,
-- 432 pelanggan, 3 PO, 3 SP, dan 16 lead tetap di id 1 dan kini tampil "Hendri".
--
-- Sales "Hendri" lama (id 15: nonaktif, tanpa akun, 0 pelanggan/PO/SP/penawaran/lead)
-- diberi nama "Hendri (lama)". Nama sales unik (lower(nama)), dan penautan sales dari
-- sheet mencocokkan nama persis — jadi teks "Hendri" kini tertaut ke id 1.
-- tautan_sales_baris (riwayat penautan dari sheet, 432 baris) ikut 15 → 1 seperti
-- berkas 80, supaya batalkan_tautan_sales tetap mengenali pelanggan itu.
-- Teks bebas di leads (catatan/permintaan yang menyebut "Ahen") tidak diubah.
--
-- Data yang berubah: sales_reps.nama id 1 & 15; tautan_sales_baris.sales_rep_id 15 → 1.
-- Memulihkan (id 1 tidak punya tautan sebelum berkas ini):
--   update public.tautan_sales_baris set sales_rep_id = 15 where sales_rep_id = 1;
--   update public.sales_reps set nama = 'Ahen'   where id = 1;
--   update public.sales_reps set nama = 'Hendri' where id = 15;
-- ═══════════════════════════════════════════════════════════════════════

update public.sales_reps set nama = 'Hendri (lama)' where id = 15 and nama = 'Hendri';
update public.sales_reps set nama = 'Hendri'        where id = 1  and nama = 'Ahen';

update public.tautan_sales_baris set sales_rep_id = 1 where sales_rep_id = 15;
