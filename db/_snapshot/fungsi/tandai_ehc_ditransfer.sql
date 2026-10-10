CREATE OR REPLACE FUNCTION public.tandai_ehc_ditransfer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lama text := current_setting('rhj.batch', true);
begin
  perform set_config('rhj.batch', 'on', true);
  update public.ehc_klaim set ditransfer_pada = now()
   where transfer_batch_id = new.id and ditransfer_pada is null;
  perform set_config('rhj.batch', coalesce(v_lama, ''), true);
  return null;
end $function$;
