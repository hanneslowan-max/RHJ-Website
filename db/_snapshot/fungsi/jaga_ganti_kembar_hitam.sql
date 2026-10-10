CREATE OR REPLACE FUNCTION public.jaga_ganti_kembar_hitam()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or public.setara_owner() or old.blacklist then return new; end if;
  if public.kunci_nama_pelanggan(new.nama) is not distinct from public.kunci_nama_pelanggan(old.nama)
     and new.hp is not distinct from old.hp then
    return new;                                    -- merapikan penulisan tetap boleh
  end if;
  if exists (select 1 from public.sp_pelanggan_hitam_rinci(old.id, null, null, null) r where r.cara = 'kembar') then
    raise exception 'Pelanggan "%" cocok nama/No. HP dengan pelanggan daftar hitam — nama dan No. HP-nya hanya diubah '
                    'owner/GM (memberi pembeda melepas penahanan PO/SP-nya).', old.nama
      using errcode = '23514';
  end if;
  return new;
end $function$;
