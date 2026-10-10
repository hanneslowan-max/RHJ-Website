CREATE OR REPLACE FUNCTION public.catat_perubahan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare em text; begin
  select email into em from public.profiles where id = auth.uid();
  insert into public.audit_log (tabel, baris_id, aksi, oleh, oleh_email, sebelum, sesudah)
  values (TG_TABLE_NAME,
          coalesce(new.id, old.id),
          TG_OP,
          auth.uid(),
          em,
          case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when TG_OP in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $function$;
