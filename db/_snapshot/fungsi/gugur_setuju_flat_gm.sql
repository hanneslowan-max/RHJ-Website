CREATE OR REPLACE FUNCTION public.gugur_setuju_flat_gm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lama_flat boolean; v_baru_flat boolean;
begin
  if new.sales_rep_id is not distinct from old.sales_rep_id
     or new.harga_ok is not true or new.gm_pct_harga is not null then
    return new;
  end if;
  select (r.komisi_flat_pct is not null and not coalesce(r.sp_hanya_gm, false)) into v_lama_flat
    from public.sales_reps r where r.id = old.sales_rep_id;
  select (r.komisi_flat_pct is not null) into v_baru_flat
    from public.sales_reps r where r.id = new.sales_rep_id;
  if coalesce(v_lama_flat, false) and not coalesce(v_baru_flat, false)
     and not exists (select 1 from public.komisi_klaim k where k.so_id = new.id) then
    new.harga_ok := null; new.gm_pada := null; new.gm_oleh := null;
  end if;
  return new;
end $function$;
