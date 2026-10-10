CREATE OR REPLACE FUNCTION public.batalkan_klaim_cepat(p_klaim bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim;
begin
  select * into k from public.ehc_klaim where id = p_klaim;
  if not found then
    raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002';
  end if;
  if not public.boleh_minta_klaim_cepat(p_klaim) then
    raise exception 'Anda tidak berhak menarik permintaan klaim cepat ini.'
      using errcode = '42501';
  end if;
  if not k.cepat_minta or k.cepat_ok is not null then
    raise exception 'Klaim ini tidak sedang menunggu GM — hanya permintaan yang belum '
                    'diputus yang bisa ditarik.' using errcode = '22023';
  end if;

  perform set_config('rhj.cepat', 'on', true);
  update public.ehc_klaim
     set cepat_minta = false, cepat_alasan = null, cepat_ok = null, cepat_catatan = null,
         cepat_diminta_oleh = null, cepat_diminta_pada = null
   where id = p_klaim;
  perform set_config('rhj.cepat', 'off', true);

  insert into public.ehc_cepat_log (klaim_id, aksi, alasan, oleh)
  values (p_klaim, 'tarik', k.cepat_alasan, auth.uid());

  return 'Permintaan klaim cepat ditarik. Klaim ini kembali ikut rekap bulanan biasa.';
end $function$;
