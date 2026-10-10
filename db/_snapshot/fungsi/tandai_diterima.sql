CREATE OR REPLACE FUNCTION public.tandai_diterima(p_order bigint, p_tanggal date DEFAULT NULL::date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lengkap boolean; kurang text; sekarang text;
begin
  if not public.boleh_alur_impor() then
    raise exception 'Anda tidak berwenang menandai pesanan diterima' using errcode = '42501';
  end if;

  select status_produksi into sekarang from public.orders where id = p_order;
  if sekarang is null then raise exception 'Order #% tidak ditemukan.', p_order; end if;
  if sekarang = 'Sudah Diterima' then
    raise exception 'Order ini sudah ditandai diterima.';
  end if;
  if sekarang <> 'Proses Customs' then
    raise exception 'Belum bisa ditandai diterima: statusnya masih "%". Barang harus lewat Proses Customs dulu — isi nomor DO dan lampirannya.', sekarang
      using errcode = '42501';
  end if;

  select (count(distinct jenis) = 4) into lengkap from public.documents
   where order_id = p_order
     and jenis in ('Commercial Invoice','Packing List','Certificate of Origin','Bill of Lading');

  if not lengkap then
    select string_agg(j, ', ') into kurang from (
      select j from unnest(array['Commercial Invoice','Packing List','Certificate of Origin','Bill of Lading']) j
      except select jenis from public.documents where order_id = p_order
    ) x;
    raise exception 'Belum bisa ditandai diterima. Dokumen yang belum ada: %', kurang
      using errcode = '42501';
  end if;

  perform set_config('rhj.alur', '1', true);
  update public.orders
     set status_produksi = 'Sudah Diterima',
         tanggal_tiba = coalesce(p_tanggal, tanggal_tiba, current_date)
   where id = p_order;
  perform set_config('rhj.alur', '', true);
  return 'Sudah Diterima';
end $function$;
