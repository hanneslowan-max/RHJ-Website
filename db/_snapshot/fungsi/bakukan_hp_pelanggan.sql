CREATE OR REPLACE FUNCTION public.bakukan_hp_pelanggan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.hp is not null then new.hp := public.hp_baku(new.hp); end if;
  return new;
end $function$;
