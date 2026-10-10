CREATE OR REPLACE FUNCTION public.hitung_ulang_status(p_order bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sekarang text; dari_dok text; lengkap boolean; baru text; dok text;
begin
  select status_produksi into sekarang from public.orders where id = p_order;
  if sekarang is null then return; end if;

  dari_dok := public.tahap_dari_dokumen(p_order);

  select (count(distinct jenis) = 4) into lengkap from public.documents
   where order_id = p_order
     and jenis in ('Commercial Invoice','Packing List','Certificate of Origin','Bill of Lading');

  -- Status hanya boleh MAJU. Dokumen yang dihapus tidak menarik status
  -- mundur — kalau bisa, satu penghapusan tak sengaja akan mengacaukan
  -- catatan perjalanan yang sudah benar.
  baru := case
            when sekarang = 'Sudah Diterima' then sekarang
            when public.urutan_status(dari_dok) > public.urutan_status(sekarang) then dari_dok
            else sekarang end;
  dok  := case when lengkap then 'Lengkap' else 'Belum Lengkap' end;

  perform set_config('rhj.alur', '1', true);
  update public.orders
     set status_produksi = baru,
         status_dokumen  = dok
   where id = p_order
     and (status_produksi is distinct from baru
       or status_dokumen  is distinct from dok);
  perform set_config('rhj.alur', '', true);
end $function$;
