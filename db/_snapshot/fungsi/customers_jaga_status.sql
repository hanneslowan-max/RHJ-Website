CREATE OR REPLACE FUNCTION public.customers_jaga_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return new; end if;            -- migrasi / SQL Editor / service role
  if not public.setara_owner() then
    if (tg_op = 'INSERT' and (coalesce(new.blacklist, false) or coalesce(new.perlu_konfirmasi, false)
                              or coalesce(btrim(new.alasan_blacklist), '') <> ''
                              or coalesce(btrim(new.alasan_konfirmasi), '') <> ''))
       or (tg_op = 'UPDATE' and (new.blacklist is distinct from old.blacklist
                                 or new.alasan_blacklist is distinct from old.alasan_blacklist
                                 or new.perlu_konfirmasi is distinct from old.perlu_konfirmasi
                                 or new.alasan_konfirmasi is distinct from old.alasan_konfirmasi)) then
      raise exception 'Status pelanggan "Daftar hitam" dan "Konfirmasi sebelum kirim" (beserta alasannya) hanya diubah '
                      'owner atau GM.';
    end if;
    return new;
  end if;
  if coalesce(new.blacklist, false) and coalesce(btrim(new.alasan_blacklist), '') = ''
     and (tg_op = 'INSERT' or new.blacklist is distinct from old.blacklist
          or new.alasan_blacklist is distinct from old.alasan_blacklist) then
    raise exception 'Alasan daftar hitam wajib diisi — alasannya yang muncul saat PO/SP pelanggan ini ditolak.';
  end if;
  return new;
end $function$;
