CREATE OR REPLACE FUNCTION public.jaga_view_komisi_tertutup()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare r record; v_rel oid; v_nama text; v_cacat text;
begin
  for r in select * from pg_event_trigger_ddl_commands() loop
    v_rel := null;
    if r.classid = 'pg_rewrite'::regclass then
      select rw.ev_class into v_rel from pg_rewrite rw where rw.oid = r.objid;
    elsif r.classid = 'pg_class'::regclass then
      v_rel := r.objid;
    end if;
    continue when v_rel is null;
    select k.relname into v_nama from pg_class k
     where k.oid = v_rel and k.relnamespace = 'public'::regnamespace
       and k.relname in ('so_ringkas','so_baris_hitung','cash_belum_cocok','komisi_belum_klaim');
    continue when v_nama is null;
    v_cacat := public.view_komisi_cacat(v_rel);
    if v_cacat is not null then
      raise exception '139k/139t: view public.% kehilangan penyaring komisi (%) — sertakan lagi predikat berkas 139k dan '
                      'security_invoker (lihat ATURAN B › Akses & peran).', v_nama, v_cacat;
    end if;
  end loop;
end $function$;
