CREATE OR REPLACE FUNCTION public.hp_terdaftar(p_hp text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_hp text := public.hp_baku(p_hp);
begin
  if auth.uid() is null or not public.boleh_alur_jual() then
    raise exception 'Pemeriksaan No. HP hanya untuk pembuat Surat Pesanan.' using errcode = '42501';
  end if;
  if v_hp is null or v_hp !~ '^[1-9][0-9]{8,15}$' then return false; end if;
  return exists (select 1 from public.customers c where c.hp = v_hp);
end $function$;
