-- ═══════════════════════════════════════════════════════════════════════
-- 119 · Pelanggan milik sales nonaktif dilepas + SP pelanggan Office hanya GM/owner, tanpa komisi
--
-- Keputusan Hannes (2026-10-05 & 2026-10-06):
--
-- (1) Pelanggan yang dipegang sales NONAKTIF dianggap belum bertuan. Sales aktif pertama
--     yang membuat PO untuknya otomatis jadi pemegangnya (jalur klaim yang sudah ada:
--     po_auto_klaim_sales berkas 79; sales juga boleh mengakui yang belum bertuan untuk
--     dirinya sendiri, customers_jaga_sales). Sales lama dicatat di
--     customers.sales_rep_lama_id sebagai riwayat — hanya owner/GM/staff yang bisa
--     mengubahnya. Berlaku ke depan: begitu sales_reps.aktif berubah true → false,
--     pelanggannya ikut dilepas. Mengaktifkan lagi tidak mengembalikan pelanggannya.
--     DEV: 209 pelanggan dari 7 sales (Yohannes 81, Ryanto 57, Gugie 32, Hasan 17,
--     Gandha 11, William 9, Andi 2). Ketujuh sales itu tidak punya PO/SP/penawaran/lead,
--     jadi tidak ada dokumen atau komisi yang berpindah.
--
-- (2) Pelanggan "Office" milik GM: SP-nya hanya dibuat GM atau owner, dan tanpa komisi.
--     · sales_reps.sp_hanya_gm (baru) menandai Office (dicari lewat nama, bukan id, supaya
--       sama di PROD).
--     · Trigger so_y_hanya_gm menolak peran lain membuat SP — atau mengalihkan SP — ke
--       sales Office atau ke pelanggan yang dipegang Office. Pekerjaan lain atas SP Office
--       yang sudah ada (cek Vonny, surat jalan, invoice, pelunasan) tidak dibatasi.
--     · Komisi: komisi_flat_pct = 0 → pct baris = 0 (cabang flat di so_baris_hitung) →
--       komisi Rp 0. Akibatnya SP Office tidak masuk antrean "harga di bawah list → GM"
--       (pct tidak NULL) — wajar, yang membuatnya memang GM/owner.
--     DEV: Office (id 23) memegang 236 pelanggan, 1 PO, 0 SP, 0 klaim komisi → tidak ada
--     angka lama yang bergeser.
--
-- Data yang berubah: customers.sales_rep_id → NULL (+ sales_rep_lama_id) untuk pelanggan
--   sales nonaktif; sales_reps Office: sp_hanya_gm = true, komisi_flat_pct = 0.
-- Memulihkan:
--   (1) update public.customers set sales_rep_id = sales_rep_lama_id
--        where sales_rep_id is null and sales_rep_lama_id is not null;
--   (2) update public.sales_reps set sp_hanya_gm = false, komisi_flat_pct = null
--        where lower(nama) = 'office';
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) pelanggan sales nonaktif ────────────────────────────────────────
alter table public.customers
  add column if not exists sales_rep_lama_id bigint
    references public.sales_reps(id) on delete set null;
comment on column public.customers.sales_rep_lama_id is
  'Sales pemegang sebelumnya yang sudah nonaktif — riwayat, diisi sistem (berkas 119).';

-- Riwayat diisi sistem, bukan klien: sales tidak bisa menulisnya lewat REST.
create or replace function public.customers_jaga_sales_lama()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.peran_saya() in ('owner','gm','staff') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.sales_rep_lama_id := null;
  else
    new.sales_rep_lama_id := old.sales_rep_lama_id;
  end if;
  return new;
end $$;
revoke all on function public.customers_jaga_sales_lama() from public, anon, authenticated;

create or replace trigger customers_jaga_sales_lama
  before insert or update of sales_rep_lama_id on public.customers
  for each row execute function public.customers_jaga_sales_lama();

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

create or replace trigger sales_reps_lepas_pelanggan
  after update of aktif on public.sales_reps
  for each row execute function public.lepas_pelanggan_sales_nonaktif();

-- Yang sudah nonaktif hari ini
update public.customers c
   set sales_rep_lama_id = c.sales_rep_id, sales_rep_id = null
  from public.sales_reps r
 where r.id = c.sales_rep_id and r.aktif = false;

-- ── (2) Office: SP hanya GM/owner, tanpa komisi ─────────────────────────
alter table public.sales_reps
  add column if not exists sp_hanya_gm boolean not null default false;
comment on column public.sales_reps.sp_hanya_gm is
  'SP atas nama sales ini / pelanggan yang dipegangnya hanya dibuat GM atau owner (Office, berkas 119).';

update public.sales_reps
   set sp_hanya_gm = true, komisi_flat_pct = 0
 where lower(nama) = 'office';

create or replace function public.sp_khusus_gm(p_rep bigint, p_customer bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sales_reps r where r.id = p_rep and r.sp_hanya_gm)
      or exists (select 1 from public.customers c
                   join public.sales_reps r on r.id = c.sales_rep_id
                  where c.id = p_customer and r.sp_hanya_gm)
$$;
revoke all on function public.sp_khusus_gm(bigint, bigint) from public, anon, authenticated;

create or replace function public.jaga_sp_hanya_gm()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_nama text;
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;
  if not public.sp_khusus_gm(new.sales_rep_id, new.customer_id) then return new; end if;
  -- SP yang memang sudah milik Office boleh dikerjakan peran lain (cek Vonny, tautkan
  -- pelanggan, dst.) — yang ditolak hanya membuat atau MENGALIHKAN SP ke Office.
  if tg_op = 'UPDATE' and public.sp_khusus_gm(old.sales_rep_id, old.customer_id) then
    return new;
  end if;
  select r.nama into v_nama
    from public.sales_reps r
   where r.sp_hanya_gm
     and (r.id = new.sales_rep_id
          or r.id = (select c.sales_rep_id from public.customers c where c.id = new.customer_id))
   limit 1;
  raise exception 'SP untuk pelanggan % hanya dibuat GM atau owner (pelanggan kantor, tanpa komisi). '
                  'Minta GM yang membuatkan SP-nya.', coalesce(v_nama, 'Office')
    using errcode = '42501';
end $$;
revoke all on function public.jaga_sp_hanya_gm() from public, anon, authenticated;

create or replace trigger so_y_hanya_gm
  before insert or update of sales_rep_id, customer_id on public.sales_orders
  for each row execute function public.jaga_sp_hanya_gm();
