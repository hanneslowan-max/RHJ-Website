CREATE OR REPLACE FUNCTION public.boleh_massal(p_jenis text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case p_jenis
           when 'harga'    then public.setara_owner()
           when 'hpp'      then public.boleh_ubah_hpp()
           when 'kelompok' then public.boleh_ubah_impor()
           when 'bracket'  then public.boleh_ubah_impor()
           when 'bahan'    then public.boleh_ubah_impor()
           when 'ukuran'   then public.boleh_ubah_impor()
           else false
         end
$function$;
