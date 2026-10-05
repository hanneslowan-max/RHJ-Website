-- 118: keputusan Hannes (2026-10-05)
--
-- (1) Pelanggan milik sales NONAKTIF dianggap belum bertuan. Sales aktif pertama yang
--     memakainya (PO / penawaran) otomatis jadi pemegangnya lewat jalur klaim yang sudah
--     ada (po_auto_klaim_sales, customers_jaga_sales: sales boleh mengakui yang belum
--     bertuan). Sales lama dicatat di customers.sales_rep_lama_id sebagai riwayat.
--     Berlaku juga ke depan: begitu sebuah sales_reps dinonaktifkan, pelanggannya dilepas.
--
-- (2) Pelanggan "Office" (sales_reps id 23) milik GM: GM yang membuat SP-nya, tanpa komisi.
--     Caranya: komisi_flat_pct = 0 → pct baris SP Office = 0 (cabang flat di so_baris_hitung
--     paling atas) sehingga komisi Rp 0. Pelanggan Office tetap terkunci dari sales.
--     Efek samping yang disadari: SP rep flat tidak masuk antrean "menunggu GM" untuk harga
--     di bawah price list (ada_bawah_list = pct IS NULL); untuk Office yang membuat SP-nya
--     memang GM sendiri.
--
-- Memulihkan (1): update customers set sales_rep_id = sales_rep_lama_id, sales_rep_lama_id = null
--                 where sales_rep_lama_id is not null and sales_rep_id is null;
-- Memulihkan (2): update sales_reps set komisi_flat_pct = null where id = 23;

alter table public.customers
  add column if not exists sales_rep_lama_id bigint references public.sales_reps(id);
comment on column public.customers.sales_rep_lama_id is
  'Sales pemegang sebelumnya yang sudah nonaktif (riwayat; berkas 118).';

update public.customers c
   set sales_rep_lama_id = c.sales_rep_id, sales_rep_id = null
  from public.sales_reps r
 where r.id = c.sales_rep_id and r.aktif = false;

create or replace function public.lepas_pelanggan_sales_nonaktif()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.aktif, true) and new.aktif = false then
    update public.customers
       set sales_rep_lama_id = sales_rep_id, sales_rep_id = null
     where sales_rep_id = new.id;
  end if;
  return new;
end $$;
revoke all on function public.lepas_pelanggan_sales_nonaktif() from public, anon, authenticated;

drop trigger if exists sales_reps_lepas_pelanggan on public.sales_reps;
create trigger sales_reps_lepas_pelanggan
  after update of aktif on public.sales_reps
  for each row execute function public.lepas_pelanggan_sales_nonaktif();

update public.sales_reps set komisi_flat_pct = 0 where id = 23;   -- Office (GM), tanpa komisi
