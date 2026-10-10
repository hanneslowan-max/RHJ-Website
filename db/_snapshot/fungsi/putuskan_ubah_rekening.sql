CREATE OR REPLACE FUNCTION public.putuskan_ubah_rekening(p_id bigint, p_setuju boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u public.pic_rekening_ubah;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan perubahan rekening.';
  end if;
  select * into u from public.pic_rekening_ubah where id = p_id and status = 'menunggu';
  if not found then raise exception 'Usulan tidak ditemukan atau sudah diputus.'; end if;
  if p_setuju then
    perform set_config('rhj.ubah_rekening', 'on', true);
    update public.customer_pics
       set bank = u.bank, no_rekening = u.no_rekening, atas_nama = u.atas_nama
     where id = u.pic_id;
    perform set_config('rhj.ubah_rekening', 'off', true);
  end if;
  update public.pic_rekening_ubah
     set status = case when p_setuju then 'disetujui' else 'ditolak' end,
         diputus_oleh = auth.uid(), diputus_pada = now()
   where id = p_id;
end $function$;
