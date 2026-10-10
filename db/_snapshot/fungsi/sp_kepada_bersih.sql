CREATE OR REPLACE FUNCTION public.sp_kepada_bersih()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.kepada is null or (tg_op = 'UPDATE' and new.kepada is not distinct from old.kepada) then return new; end if;
  new.kepada := btrim(public.teks_tanpa_format(new.kepada));
  if auth.uid() is not null and coalesce(public.peran_saya(), '') not in ('owner','gm','staff')
     and public.ada_huruf_non_latin(new.kepada) then
    raise exception 'Kepada "%" memuat huruf atau simbol khusus di luar huruf Latin biasa (mis. huruf Kiril/Yunani atau simbol yang mirip huruf). Ketik ulang '
                    'dengan huruf biasa; bila memang perlu, minta owner/GM/staff.', new.kepada
      using errcode = 'P0001';
  end if;
  return new;
end $function$;
