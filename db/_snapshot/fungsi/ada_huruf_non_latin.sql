CREATE OR REPLACE FUNCTION public.ada_huruf_non_latin(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select regexp_replace(coalesce(public.teks_tanpa_format(p), ''),
           '[\t\n\r -~ ©®°²³¹¼-¾‐-—‘’“”…™−ªºÀ-ÖØ-öø-įĲ-ķĹ-ľŁ-ňŊ-žƠơƯưḀ-ẕẠ-ỹ]',
           '', 'g') <> ''
$function$;
