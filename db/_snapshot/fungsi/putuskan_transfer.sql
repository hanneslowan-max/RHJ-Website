CREATE OR REPLACE FUNCTION public.putuskan_transfer(p_id bigint, p_setuju boolean, p_catatan text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.transfer_pengajuan;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh menyetujui transfer.'
      using errcode = '42501';
  end if;
  select * into v from public.transfer_pengajuan where id = p_id;
  if not found then
    raise exception 'Pengajuan #% tidak ada.', p_id using errcode = 'P0002';
  end if;
  if v.status <> 'menunggu' then
    raise exception 'Pengajuan #% sudah berstatus "%". Yang sudah diputus tidak bisa '
                    'diputus lagi.', p_id, v.status using errcode = '22023';
  end if;
  -- Menolak tanpa alasan membuat finance menebak apa yang harus dibetulkan.
  if not p_setuju and coalesce(btrim(coalesce(p_catatan,'')), '') = '' then
    raise exception 'Penolakan wajib beralasan — finance harus tahu apa yang perlu '
                    'dibereskan sebelum mengajukan lagi.' using errcode = '22023';
  end if;

  update public.transfer_pengajuan
     set status = case when p_setuju then 'disetujui' else 'ditolak' end,
         catatan_gm = nullif(btrim(coalesce(p_catatan,'')), ''),
         diputus_oleh = auth.uid(), diputus_pada = now()
   where id = p_id;

  return case when p_setuju
    then 'Pengajuan #' || p_id || ' (' || v.jenis || ' ' || v.bulan || ', '
       || v.jumlah_klaim || ' klaim) DISETUJUI. Finance boleh mentransfer lalu menandainya.'
    else 'Pengajuan #' || p_id || ' DITOLAK. Finance bisa membetulkan lalu mengajukan lagi.'
  end;
end $function$;
