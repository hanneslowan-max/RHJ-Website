CREATE OR REPLACE FUNCTION public.po_catat_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    new.dibuat_oleh := auth.uid();
  else
    new.diubah_pada := now();
    new.diubah_oleh := auth.uid();
  end if;
  return new;
end $function$;
