CREATE OR REPLACE FUNCTION public.isi_referensi_batch(p_batch bigint, p_ref text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengisi referensi transfer.'
      using errcode = '42501';
  end if;
  if coalesce(btrim(p_ref), '') = '' then
    raise exception 'Nomor referensi tidak boleh kosong.';
  end if;
  update public.transfer_batch set no_referensi = btrim(p_ref) where id = p_batch;
  if not found then
    raise exception 'Batch #% tidak ditemukan.', p_batch;
  end if;
end $function$;
