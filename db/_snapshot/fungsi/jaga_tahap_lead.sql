CREATE OR REPLACE FUNCTION public.jaga_tahap_lead()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(current_setting('rhj.crm', true), '') = '1' then
    return new;                                   -- dari hitung ulang, boleh
  end if;
  if new.tahap is distinct from old.tahap then
    raise exception 'Tahap lead tidak bisa diubah manual. Tahap mengikuti kejadian: penawaran, follow up, order, batal.'
      using errcode = '42501';
  end if;
  return new;
end $function$;
