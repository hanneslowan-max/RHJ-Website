CREATE OR REPLACE FUNCTION public.quote_lines_isi_set()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.set_id is null then
    new.set_isi := null;
  else
    select jsonb_agg(jsonb_build_object('product_id', c.product_id, 'qty', c.qty) order by c.urut, c.id)
      into new.set_isi
      from public.product_set_components c
     where c.set_id = new.set_id;
  end if;
  return new;
end $function$;
