CREATE OR REPLACE FUNCTION public.kolom_massal(p_jenis text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_jenis
           when 'kelompok' then 'kelompok'
           when 'bracket'  then 'fungsi'
           when 'bahan'    then 'bahan'
           when 'ukuran'   then 'diameter_mm'
           else null end
$function$;
