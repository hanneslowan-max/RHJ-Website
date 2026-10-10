CREATE OR REPLACE FUNCTION public.jaga_total_sp_vs_po()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ids bigint[];
  i   bigint;
begin
  if TG_OP = 'INSERT' then
    select array_agg(distinct so_id) into ids from baru;
  elsif TG_OP = 'DELETE' then
    select array_agg(distinct so_id) into ids from lama;
  else
    select array_agg(distinct so_id) into ids
      from (select so_id from baru union select so_id from lama) t;
  end if;

  if ids is null then return null; end if;
  foreach i in array ids loop
    perform public.periksa_total_sp(i);
  end loop;
  return null;
end $function$;
