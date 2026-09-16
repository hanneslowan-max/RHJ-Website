-- Berkas 79: auto-save penanggung jawab sales ke pelanggan saat PO dibuat.
-- Masalah: pelanggan tanpa sales_rep_id → sales pilih dirinya tiap bikin PO, berulang.
-- Solusi: trigger AFTER INSERT purchase_orders → set customers.sales_rep_id = PO.sales_rep_id
--   HANYA bila pelanggan masih kosong (tak merebut milik sales lain). Lain kali PO/SP untuk
--   pelanggan itu terisi sendiri (FE setelSalesDariPelanggan membaca customers.sales_rep_id).
-- Aman:
--   * where sales_rep_id is null → hanya klaim yang belum bertuan.
--   * update customers tetap lewat trigger customers_jaga_sales (aturan lama utuh: 'sales' hanya boleh
--     ambil untuk diri sendiri; owner/gm/staff bebas). SECURITY DEFINER tak mengubah auth.uid()/peran.
--   * blok EXCEPTION WHEN OTHERS → bila klaim ditolak, PO TETAP tersimpan (auto-save = bonus, bukan syarat).
-- Murni DB, tak perlu ubah index.html. Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke prod.

create or replace function public.po_auto_klaim_sales()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.sales_rep_id is not null and new.customer_id is not null then
    begin
      update public.customers c
         set sales_rep_id = new.sales_rep_id
       where c.id = new.customer_id and c.sales_rep_id is null;
    exception when others then
      null;
    end;
  end if;
  return new;
end $$;

drop trigger if exists po_z_auto_klaim_sales on public.purchase_orders;
create trigger po_z_auto_klaim_sales after insert on public.purchase_orders
  for each row execute function public.po_auto_klaim_sales();
