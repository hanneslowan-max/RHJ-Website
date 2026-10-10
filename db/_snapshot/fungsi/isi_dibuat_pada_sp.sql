CREATE OR REPLACE FUNCTION public.isi_dibuat_pada_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is not null then new.dibuat_pada := now(); end if;
  return new;
end $function$;
