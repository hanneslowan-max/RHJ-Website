CREATE OR REPLACE FUNCTION public.tarik_pengajuan_transfer(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.transfer_pengajuan;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh menarik pengajuan.'
      using errcode = '42501';
  end if;
  select * into v from public.transfer_pengajuan where id = p_id;
  if not found then
    raise exception 'Pengajuan #% tidak ada.', p_id using errcode = 'P0002';
  end if;
  if v.status <> 'menunggu' then
    raise exception 'Pengajuan #% berstatus "%" — hanya yang masih menunggu GM yang '
                    'bisa ditarik.', p_id, v.status using errcode = '22023';
  end if;
  delete from public.transfer_pengajuan where id = p_id;
  return 'Pengajuan #' || p_id || ' ditarik. Silakan ajukan lagi kalau daftarnya sudah benar.';
end $function$;
