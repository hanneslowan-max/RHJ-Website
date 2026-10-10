CREATE OR REPLACE FUNCTION public.jaga_anak_klaim_ehc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ids bigint[] := array[new.klaim_id];
begin
  if tg_op = 'UPDATE' then v_ids := v_ids || old.klaim_id; end if;
  if exists (select 1 from public.ehc_klaim k
              where k.id = any(v_ids) and (k.status <> 'diajukan' or k.transfer_batch_id is not null)) then
    raise exception 'Klaim EHC #% sudah diputus atau ber-batch — alokasi SP dan lampirannya beku.', new.klaim_id
      using errcode = '42501';
  end if;
  return new;
end $function$;
