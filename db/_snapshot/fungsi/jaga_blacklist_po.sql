CREATE OR REPLACE FUNCTION public.jaga_blacklist_po()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.customers;
begin
  if new.customer_id is null then return new; end if;
  if auth.uid() is not null and public.peran_saya() = 'sales' and not public.pelanggan_saya(new.customer_id) then
    return new;
  end if;
  select * into v from public.customers where id = new.customer_id;
  if found and v.blacklist then
    if auth.uid() is not null and public.peran_saya() = 'sales' and not public.pic_pelanggan_saya(v.id) then
      raise exception 'Pelanggan PO ini masuk daftar hitam — PO tidak bisa dibuat. Hubungi owner/GM.';
    end if;
    raise exception 'Pelanggan % masuk daftar hitam (%). PO tidak bisa dibuat.',
      v.nama, coalesce(v.alasan_blacklist, 'tanpa keterangan');
  end if;
  -- 139s (review 139 no. 2): kembaran pelanggan daftar hitam (nama/No. HP, sekarang atau dulu) — PO baru / ganti
  -- pelanggan PO hanya oleh owner/GM (sama dengan SP)
  if auth.uid() is not null and not public.setara_owner()
     and (tg_op = 'INSERT' or new.customer_id is distinct from old.customer_id)
     and public.sp_pelanggan_hitam(new.customer_id, null, null, null) is not null then
    raise exception 'Pelanggan PO ini cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — PO tidak bisa dibuat. '
                    'Bila ini perusahaan/orang lain, owner/GM memberi pembeda pada nama atau memperbaiki No. HP '
                    'pelanggannya di tab Pelanggan.' using errcode = '23514';
  end if;
  return new;
end $function$;
