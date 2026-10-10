CREATE OR REPLACE FUNCTION public.putuskan_klaim_cepat(p_klaim bigint, p_setuju boolean, p_catatan text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan pencairan cepat.' using errcode = '42501';
  end if;
  if p_setuju is distinct from false then
    raise exception 'Layar ini versi lama — muat ulang halaman. Persetujuan EHC cepat kini memeriksa versi klaim.'
      using errcode = '0A000';
  end if;
  return public.putuskan_klaim_cepat_v(p_klaim, false, p_catatan, null, null);
end $function$;
