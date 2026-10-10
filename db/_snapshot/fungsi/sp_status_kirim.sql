CREATE OR REPLACE FUNCTION public.sp_status_kirim(p_ids bigint[])
 RETURNS TABLE(so_id bigint, hitam boolean, hitam_pesan text, konfirmasi boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s record; r record; v_nama text; v_alasan text; v_sebut boolean;
        v_sales boolean := coalesce(public.peran_saya(), '') = 'sales'; v_baca boolean := public.boleh_baca();
begin
  if auth.uid() is null then return; end if;
  for s in
    select x.* from public.sales_orders x
     where x.id = any (coalesce(p_ids, '{}'::bigint[]))
       and public.sp_terbaca(x.sales_rep_id, x.dibuat_oleh, x.batal, x.no_surat_jalan, x.vonny_ok)
  loop
    so_id := s.id; hitam := false; hitam_pesan := null;
    select coalesce(c.perlu_konfirmasi, false) into konfirmasi from public.customers c where c.id = s.customer_id;
    konfirmasi := coalesce(konfirmasi, false);   -- cermin gerbang 2 gerbang_kirim_sp (pelanggan SP)
    select * into r from public.sp_pelanggan_hitam_rinci(s.customer_id, s.po_id, s.kepada, s.telp) limit 1;
    if r.id is not null then
      hitam := true;
      select c.nama, c.alasan_blacklist into v_nama, v_alasan from public.customers c where c.id = r.id;
      -- 139x: = sp_daftar_hitam_cek — sales hanya pada cara 'pelanggan' yang ia pegang
      v_sebut := v_baca and (not v_sales or (r.cara = 'pelanggan' and public.pic_pelanggan_saya(r.id)));
      hitam_pesan := case r.cara
        when 'pelanggan' then 'Pelanggan Surat Pesanan ini masuk daftar hitam'
                              || case when v_sebut then ' ("' || v_nama || '", ' || coalesce(v_alasan, 'tanpa keterangan') || ')' else '' end
        when 'kembar'    then 'Pelanggan Surat Pesanan ini cocok nama/No. HP dengan pelanggan daftar hitam'
                              || case when v_sebut then ' "' || v_nama || '"' else '' end
        else 'Nama/No. HP Surat Pesanan ini cocok dengan pelanggan daftar hitam'
             || case when v_sebut then ' "' || v_nama || '"' else '' end end;
    end if;
    return next;
  end loop;
end $function$;
