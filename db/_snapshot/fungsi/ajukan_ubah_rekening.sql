CREATE OR REPLACE FUNCTION public.ajukan_ubah_rekening(p_pic bigint, p_bank text, p_rek text, p_atas_nama text, p_alasan text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v public.customer_pics;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengajukan perubahan rekening.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Alasan perubahan rekening wajib diisi.' using errcode = '22023';
  end if;
  select * into v from public.customer_pics where id = p_pic;
  if not found then raise exception 'PIC tidak ditemukan.' using errcode = 'P0002'; end if;
  -- Gerbang pemilik. Tanpa ini, seorang sales bisa mengusulkan rekening
  -- PIC pelanggan sales lain diganti menjadi rekeningnya sendiri, dan
  -- antrean GM tidak menunjukkan apa pun yang mencurigakan.
  if not public.pic_pelanggan_saya(v.customer_id) then
    raise exception 'Pelanggan ini bukan pelanggan Anda. Perubahan rekening PIC hanya bisa '
                    'diusulkan sales yang memegang pelanggan itu — kalau memang perlu, '
                    'mintalah lewat orang yang memegangnya.' using errcode = '42501';
  end if;
  insert into public.pic_rekening_ubah
    (pic_id, lama_bank, lama_no_rekening, lama_atas_nama,
     bank, no_rekening, atas_nama, alasan, diajukan_oleh)
  values (p_pic, v.bank, v.no_rekening, v.atas_nama,
          p_bank, p_rek, p_atas_nama, p_alasan, auth.uid())
  returning id into v_id;
  return v_id;
end $function$;
