CREATE OR REPLACE FUNCTION public.tahan_daftar_hitam_sp(p_no_sp text, p_customer bigint, p_po bigint, p_kepada text, p_telp text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_c public.customers; v_link text;
begin
  select * into r from public.sp_pelanggan_hitam_rinci(p_customer, p_po, p_kepada, p_telp) limit 1;
  if r.id is null then return; end if;
  select * into v_c from public.customers where id = r.id;
  if r.cara = 'pelanggan' then
    raise exception 'Pelanggan Surat Pesanan % ("%") masuk daftar hitam (%). Barangnya ditahan total — izin kirim tidak '
                    'membukanya. Owner/GM mencabut daftar hitamnya di tab Pelanggan, atau membatalkan sisa SP. Invoice dan '
                    'pelunasan barang yang sudah keluar tetap bisa.',
      coalesce(p_no_sp, '(baru)'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
  end if;
  if r.cara = 'kembar' then
    select x.nama into v_link from public.customers x
     where x.id = coalesce(p_customer, (select p.customer_id from public.purchase_orders p where p.id = p_po));
    raise exception 'Pelanggan Surat Pesanan % ("%") cocok nama/No. HP dengan pelanggan daftar hitam "%" (%). Barangnya '
                    'ditahan. Bila ini perusahaan/orang lain, owner/GM memberi pembeda pada nama (mis. kota/cabang) atau '
                    'memperbaiki No. HP pelanggannya di tab Pelanggan; atau mencabut daftar hitamnya.',
      coalesce(p_no_sp, '(baru)'), coalesce(v_link, '—'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
      using errcode = '23514';
  end if;
  raise exception 'Nama/No. HP Surat Pesanan % cocok dengan pelanggan daftar hitam "%" (%). Barangnya ditahan. Bila ini '
                  'perusahaan/orang lain, ubah Kepada/No. HP lewat Minta ubah SP (beri pembeda, mis. kota/cabang — '
                  'disetujui GM), lalu Vonny/owner menautkannya; atau owner/GM mencabut daftar hitamnya.',
    coalesce(p_no_sp, '(baru)'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
end $function$;
