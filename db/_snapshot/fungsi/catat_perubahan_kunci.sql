CREATE OR REPLACE FUNCTION public.catat_perubahan_kunci()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare em text; v_kunci text; v_id bigint;
begin
  select email into em from public.profiles where id = auth.uid();
  v_kunci := TG_ARGV[0];
  -- baris_id diambil dari kolom yang disebut trigger, lewat jsonb — satu
  -- fungsi untuk berapa pun tabel, tanpa SQL dinamis per tabel.
  v_id := nullif(coalesce(to_jsonb(new) ->> v_kunci, to_jsonb(old) ->> v_kunci), '')::bigint;
  insert into public.audit_log (tabel, baris_id, aksi, oleh, oleh_email, sebelum, sesudah)
  values (TG_TABLE_NAME, v_id, TG_OP, auth.uid(), em,
          case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when TG_OP in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $function$;
