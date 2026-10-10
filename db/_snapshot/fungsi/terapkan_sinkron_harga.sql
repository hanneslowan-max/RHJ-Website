CREATE OR REPLACE FUNCTION public.terapkan_sinkron_harga(p_sumber_id bigint, p_baris jsonb, p_ringkas jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare n_log bigint; em text;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh menerapkan sinkron harga';
  end if;

  insert into public.price_list (product_id, harga, berlaku_dari, catatan)
  select (b->>'product_id')::bigint, (b->>'harga')::numeric, current_date, 'sinkron Google Sheets'
    from jsonb_array_elements(p_baris) b
  on conflict (product_id, berlaku_dari)
  do update set harga = excluded.harga, catatan = excluded.catatan;

  select email into em from public.profiles where id = auth.uid();

  insert into public.sync_log (sumber_id, hasil, baris_dibaca, naik, turun, baru,
                               hilang, sama, tak_dikenal, rincian, oleh, oleh_email)
  values (p_sumber_id, 'diterapkan',
          coalesce((p_ringkas->>'baris_dibaca')::int, 0), coalesce((p_ringkas->>'naik')::int, 0),
          coalesce((p_ringkas->>'turun')::int, 0),        coalesce((p_ringkas->>'baru')::int, 0),
          coalesce((p_ringkas->>'hilang')::int, 0),       coalesce((p_ringkas->>'sama')::int, 0),
          coalesce((p_ringkas->>'tak_dikenal')::int, 0),
          p_ringkas, auth.uid(), em)
  returning id into n_log;

  update public.sync_sumber set terakhir_tarik = now() where id = p_sumber_id;
  return n_log;
end $function$;
