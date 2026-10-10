CREATE OR REPLACE FUNCTION public.setujui_ubah_lepas_hitam(p_id bigint, p_catatan text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r text;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan usulan perubahan.' using errcode = '42501';
  end if;
  perform set_config('rhj.lepas_hitam', 'on', true);
  r := public.putuskan_ubah(p_id, true,
         concat_ws(' ', '[melepas penahanan daftar hitam]', nullif(btrim(coalesce(p_catatan, '')), '')));
  perform set_config('rhj.lepas_hitam', '', true);
  return r;
end $function$;
