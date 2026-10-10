CREATE OR REPLACE FUNCTION public.setujui_klaim_ehc_massal(p_daftar jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v jsonb; v_ok jsonb := '[]'::jsonb; v_lewat jsonb := '[]'::jsonb; v_gagal jsonb := '[]'::jsonb;
        v_total numeric := 0; v_n integer; v_d integer; v_kosong integer;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh menyetujui klaim EHC.' using errcode = '42501';
  end if;
  if p_daftar is null or jsonb_typeof(p_daftar) <> 'array' or jsonb_array_length(p_daftar) not between 1 and 100 then
    raise exception 'Daftar klaim harus berisi 1 sampai 100 butir {klaim, versi}.' using errcode = '22023';
  end if;
  begin
    select count(*), count(distinct x.klaim), count(*) filter (where x.klaim is null)
      into v_n, v_d, v_kosong
      from jsonb_to_recordset(p_daftar) as x(klaim bigint, versi timestamptz);
  exception when others then
    raise exception 'Daftar klaim tidak terbaca — tiap butir {klaim, versi}.' using errcode = '22023';
  end;
  if v_kosong > 0 or v_d <> v_n then
    raise exception 'Daftar klaim berisi butir tanpa nomor klaim atau klaim yang sama dua kali.' using errcode = '22023';
  end if;
  for r in select x.klaim, x.versi from jsonb_to_recordset(p_daftar) as x(klaim bigint, versi timestamptz)
            order by x.klaim loop
    if public.klaim_ehc_lintas(r.klaim) then
      v_lewat := v_lewat || jsonb_build_object('klaim', r.klaim, 'alasan', 'lintas customer — putuskan satu per satu');
      continue;
    end if;
    begin
      v := public.putuskan_klaim_ehc_inti(r.klaim, true, null, r.versi, true);
      v_ok := v_ok || jsonb_build_object('klaim', r.klaim, 'nominal', v->'nominal');
      v_total := v_total + coalesce((v->>'nominal')::numeric, 0);
    exception when others then
      v_gagal := v_gagal || jsonb_build_object('klaim', r.klaim, 'kode', sqlstate, 'pesan', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('disetujui', v_ok, 'dilewati', v_lewat, 'gagal', v_gagal, 'total', v_total);
end $function$;
