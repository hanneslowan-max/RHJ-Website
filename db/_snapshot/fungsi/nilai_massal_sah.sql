CREATE OR REPLACE FUNCTION public.nilai_massal_sah(p_jenis text, p_nilai text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_nilai is null then true                    -- mengosongkan selalu boleh
    when p_jenis = 'bracket' then p_nilai in ('Hidup / Swivel','Mati / Rigid','Rem / Brake')
    when p_jenis = 'bahan'   then p_nilai in ('CB','Karet','Nylon','Polyurethane')
    when p_jenis = 'ukuran'  then p_nilai ~ '^[0-9]+([.,][0-9]+)?$' and replace(p_nilai,',','.')::numeric > 0
    when p_jenis = 'kelompok' then length(btrim(p_nilai)) > 0
    else false end
$function$;
