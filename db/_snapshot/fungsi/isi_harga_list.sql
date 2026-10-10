CREATE OR REPLACE FUNCTION public.isi_harga_list()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tgl date; v_list numeric;
begin
  -- Tanggal SP, bukan hari ini: harga_list adalah harga yang berlaku SAAT
  -- SP dibuat. Kalau dipakai current_date, price list yang naik bulan
  -- depan diam-diam mengubah komisi SP yang sudah jalan.
  select tanggal into v_tgl from public.sales_orders where id = new.so_id;
  v_list := public.harga_berlaku_hitung(new.product_id, coalesce(v_tgl, current_date));

  -- Pada UPDATE yang tidak menyentuh produk, angka lama DIPERTAHANKAN —
  -- ia memang sudah beku sejak barisnya dibuat.
  if tg_op = 'UPDATE'
     and new.product_id is not distinct from old.product_id
     and old.harga_list is not null then
    new.harga_list := old.harga_list;
  else
    new.harga_list := v_list;   -- null kalau produknya belum punya price list
  end if;
  return new;
end $function$;
