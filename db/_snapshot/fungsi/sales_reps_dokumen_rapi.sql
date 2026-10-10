CREATE OR REPLACE FUNCTION public.sales_reps_dokumen_rapi()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.nama_dokumen  := nullif(btrim(coalesce(new.nama_dokumen, '')), '');
  new.hp_dokumen    := public.hp_baku(new.hp_dokumen);
  new.email_dokumen := nullif(lower(btrim(coalesce(new.email_dokumen, ''))), '');
  return new;
end $function$;
