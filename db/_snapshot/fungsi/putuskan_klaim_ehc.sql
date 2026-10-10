CREATE OR REPLACE FUNCTION public.putuskan_klaim_ehc(p_klaim bigint, p_setuju boolean, p_catatan text DEFAULT NULL::text, p_versi timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; v_belum text; v_sp text; v_kas text;
begin
  v := public.putuskan_klaim_ehc_inti(p_klaim, p_setuju, p_catatan, p_versi, false);
  select string_agg(e->>'no_sp', ', ' order by (e->>'so_id')::bigint) filter (where not (e->>'lunas')::boolean),
         string_agg(e->>'no_sp', ', ' order by (e->>'so_id')::bigint),
         string_agg(e->>'no_sp', ', ' order by (e->>'so_id')::bigint) filter (where (e->>'tertutup')::boolean)
    into v_belum, v_sp, v_kas
    from jsonb_array_elements(v->'alokasi') e;
  if p_setuju then
    return 'DISETUJUI. Klaim EHC #' || p_klaim || ' (' || coalesce(public.rp_teks((v->>'nominal')::numeric), '-')
        || ') dibayar finance mulai tgl 20 begitu semua SP lunas' || coalesce('; SP ' || v_belum || ' belum lunas', '') || '.';
  end if;
  return 'DITOLAK. Saldo ' || coalesce(public.rp_teks((v->>'nominal')::numeric), '-') || ' kembali ke SP ' || coalesce(v_sp, '-')
      || coalesce('; SP ' || v_kas || ' sudah tertutup komisi — saldonya masuk kas sales', '') || '.';
end $function$;
