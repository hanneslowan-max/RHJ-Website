CREATE OR REPLACE FUNCTION public.teks_tanpa_format(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select normalize(regexp_replace(
    replace(replace(replace(replace(replace(replace(replace(regexp_replace(p,
    '[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ؀-؅۝܏࣢￰-￻\U000110bd\U000110cd\U00013430-\U0001343f\U0001bca0-\U0001bca3\U0001d173-\U0001d17a\U000e0000-\U000e0fff]',
    '', 'g'),
    U&'\FB00', 'ff'), U&'\FB01', 'fi'), U&'\FB02', 'fl'), U&'\FB03', 'ffi'), U&'\FB04', 'ffl'), U&'\FB05', 'st'), U&'\FB06', 'st'),
    '[\u0085  -     　]', ' ', 'g'),
    NFC)
$function$;
