CREATE OR REPLACE FUNCTION public.quotes_kontak_pelanggan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.customer_id is null or (new.up is null and new.email is null) then return null; end if;
  update public.customers c
     set pic   = case when nullif(btrim(coalesce(c.pic, '')), '') is null and new.up is not null then new.up else c.pic end,
         email = case when nullif(btrim(coalesce(c.email, '')), '') is null and new.email is not null then new.email else c.email end
   where c.id = new.customer_id
     and ((nullif(btrim(coalesce(c.pic, '')), '') is null and new.up is not null)
          or (nullif(btrim(coalesce(c.email, '')), '') is null and new.email is not null));
  return null;
end $function$;
