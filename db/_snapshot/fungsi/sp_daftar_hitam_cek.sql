CREATE OR REPLACE FUNCTION public.sp_daftar_hitam_cek(p_customer bigint DEFAULT NULL::bigint, p_po bigint DEFAULT NULL::bigint, p_kepada text DEFAULT NULL::text, p_telp text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_c public.customers; v_po public.purchase_orders;
begin
  if auth.uid() is null or not (public.boleh_alur_jual() or public.boleh_konfirmasi_kirim()) then return null; end if;
  if public.peran_saya() = 'sales' then
    if p_customer is not null and not public.pelanggan_saya(p_customer) then return null; end if;
    if p_po is not null then
      select * into v_po from public.purchase_orders where id = p_po;
      if v_po.id is null or not (public.pelanggan_saya(v_po.customer_id)
                                 and (v_po.sales_rep_id is null or v_po.sales_rep_id = public.sales_rep_saya())) then
        return null;
      end if;
    end if;
  end if;
  select * into r from public.sp_pelanggan_hitam_rinci(p_customer, p_po, p_kepada, p_telp) limit 1;
  if r.id is null then return null; end if;
  select * into v_c from public.customers where id = r.id;
  if r.cara = 'pelanggan' then
    if public.peran_saya() <> 'sales' or public.pic_pelanggan_saya(r.id) then
      return 'Pelanggan "' || v_c.nama || '" masuk daftar hitam (' || coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
          || '). Surat Pesanan tidak bisa dibuat untuknya — owner/GM mencabut daftar hitamnya dulu bila memang boleh dilayani lagi.';
    end if;
    return 'Pelanggan SP ini masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Hubungi owner/GM.';
  end if;
  if public.setara_owner() then
    return 'peringatan: ' || case r.cara when 'kembar' then 'Pelanggan SP ini' when 'hp' then 'No. HP SP ini' else 'Nama SP ini' end
        || ' cocok dengan pelanggan daftar hitam "' || v_c.nama || '" (' || coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
        || '). SP boleh dibuat owner/GM, tetapi barangnya DITAHAN (cek Vonny & surat jalan) sampai '
        || case when r.cara = 'kembar' then 'nama/No. HP pelanggannya diberi pembeda di tab Pelanggan'
                else 'Kepada/No. HP SP diberi pembeda lewat Minta ubah SP' end
        || ', atau daftar hitamnya dicabut.';
  end if;
  if r.cara = 'kembar' then
    return 'Pelanggan ini cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. '
        || 'Bila ini perusahaan/orang lain, minta owner/GM memberi pembeda pada nama atau memperbaiki No. HP pelanggannya.';
  end if;
  return 'Nama/No. HP ini cocok dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Bila ini '
      || 'perusahaan/orang lain, beri pembeda pada namanya (mis. kota atau cabang), atau minta owner/GM.';
end $function$;
