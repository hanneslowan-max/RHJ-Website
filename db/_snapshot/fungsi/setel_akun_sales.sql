CREATE OR REPLACE FUNCTION public.setel_akun_sales(p_profile uuid, p_rep bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nama text; v_lama text;
begin
  if public.peran_saya() <> 'owner' then
    raise exception 'Hanya owner yang boleh menautkan akun ke nama sales.'
      using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile) then
    raise exception 'Akun itu tidak ada.' using errcode = 'P0002';
  end if;

  -- Satu akun hanya boleh menunjuk satu nama sales (ada unique index di
  -- profile_id). Tautan lamanya dilepas dulu, kalau tidak insert-nya
  -- ditolak dan pesannya tidak menjelaskan apa-apa.
  select r.nama into v_lama from public.sales_reps r where r.profile_id = p_profile;
  update public.sales_reps set profile_id = null where profile_id = p_profile;

  if p_rep is null then
    return coalesce(v_lama, 'Akun itu') || ' dilepas dari akunnya.';
  end if;

  select nama into v_nama from public.sales_reps where id = p_rep;
  if v_nama is null then
    raise exception 'Nama sales #% tidak ada.', p_rep using errcode = 'P0002';
  end if;
  if exists (select 1 from public.sales_reps
              where id = p_rep and profile_id is not null and profile_id <> p_profile) then
    raise exception 'Nama sales % sudah tertaut ke akun lain. Lepas dulu dari akun itu.',
      v_nama using errcode = '23505';
  end if;

  update public.sales_reps set profile_id = p_profile where id = p_rep;
  return 'Akun ini sekarang masuk sebagai ' || v_nama || '.';
end $function$;
