CREATE OR REPLACE FUNCTION public.catat_jejak_hitam()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (coalesce(new.blacklist, false) or (tg_op = 'UPDATE' and coalesce(old.blacklist, false))) then return null; end if;
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
  select new.id, x.jenis, x.nilai, coalesce(x.teks, '')
    from (values ('kunci', public.kunci_nama_pelanggan(new.nama), new.nama),
                 ('kunci', public.kunci_nama_pelanggan(new.nama_lama), new.nama_lama),
                 ('hp', new.hp, null::text),
                 ('kunci', case when tg_op = 'UPDATE' then public.kunci_nama_pelanggan(old.nama) end,
                           case when tg_op = 'UPDATE' then old.nama end),
                 ('kunci', case when tg_op = 'UPDATE' then public.kunci_nama_pelanggan(old.nama_lama) end,
                           case when tg_op = 'UPDATE' then old.nama_lama end),
                 ('hp', case when tg_op = 'UPDATE' then old.hp end, null::text)) as x(jenis, nilai, teks)
   where x.nilai is not null and (x.jenis = 'hp' or (char_length(x.nilai) >= 2 and x.nilai <> 'tanpa nama'))
  on conflict do nothing;
  return null;
end $function$;
