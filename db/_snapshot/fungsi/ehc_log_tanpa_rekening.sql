CREATE OR REPLACE FUNCTION public.ehc_log_tanpa_rekening()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if jsonb_typeof(new.data -> 'klaim') = 'object' then
    new.data := jsonb_set(new.data, '{klaim}', (new.data -> 'klaim') - array['bank','no_rekening','atas_nama']);
  end if;
  return new;
end $function$;
