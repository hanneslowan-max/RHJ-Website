-- 117: Hendri (sales_reps id 15, nonaktif, tanpa akun) = Ahen (id 1, akun sales aktif).
-- Keputusan Hannes: "Ahen itu adalah Hendri". Pelanggan yang tercatat atas nama Hendri
-- dipindah ke Ahen supaya Ahen bisa membuat penawaran & PO untuk pelanggannya sendiri.
-- Hanya customers yang memakai id 15 (leads/PO/SP/penawaran: 0 baris). Teks riwayat
-- (salesman_teks) tidak diubah.
--
-- Cadangan untuk memulihkan: customers_sales_sebelum_117 (id, sales_rep_id lama).
--   update public.customers c set sales_rep_id = b.sales_rep_id
--   from public.customers_sales_sebelum_117 b where b.id = c.id;

create table if not exists public.customers_sales_sebelum_117 as
  select id, sales_rep_id from public.customers where sales_rep_id = 15;
alter table public.customers_sales_sebelum_117 enable row level security;
revoke all on public.customers_sales_sebelum_117 from public, anon, authenticated;

update public.customers set sales_rep_id = 1 where sales_rep_id = 15;
