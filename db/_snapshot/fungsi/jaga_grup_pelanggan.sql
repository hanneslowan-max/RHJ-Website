CREATE OR REPLACE FUNCTION public.jaga_grup_pelanggan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;
  if (tg_op = 'INSERT' and new.grup_id is not null)
     or (tg_op = 'UPDATE' and new.grup_id is distinct from old.grup_id) then
    raise exception 'Grup pelanggan hanya diatur owner/GM (tab Pelanggan › Grup pelanggan).' using errcode = '42501';
  end if;
  return new;
end $function$;
