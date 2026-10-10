CREATE OR REPLACE FUNCTION public.tandai_set_sp_lama()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  s record; pl record; c record;
  a_id bigint[]; a_prod bigint[]; a_qty numeric[]; a_jenis text[];
  n int; pos int; kk int; g smallint;
  komp jsonb; perlu numeric; acc numeric; cocok boolean;
  tanda bigint[]; isi_tanda numeric[];
  n_set int := 0;
begin
  -- penanda saja: trigger baris tidak dinyalakan. SET LOCAL (bukan set_config): di Supabase hanya pernyataan SET
  -- yang diizinkan untuk parameter ini (supautils); dikembalikan ke origin di akhir fungsi.
  set local session_replication_role = replica;
  for s in
    select so.id, so.po_id
      from public.sales_orders so
     where so.po_id is not null
       and exists (select 1 from public.po_lines l
                    where l.po_id = so.po_id
                      and (l.set_id is not null or jsonb_typeof(l.set_komponen) = 'array'))
       and not exists (select 1 from public.sales_order_lines x where x.so_id = so.id and x.set_grup is not null)
     order by so.id
  loop
    select array_agg(x.id order by x.urut, x.id), array_agg(x.product_id order by x.urut, x.id),
           array_agg(x.qty order by x.urut, x.id), array_agg(x.jenis order by x.urut, x.id)
      into a_id, a_prod, a_qty, a_jenis
      from public.sales_order_lines x where x.so_id = s.id;
    n := coalesce(array_length(a_id, 1), 0);
    pos := 1; g := 0;
    for pl in
      select l.id, l.qty, l.product_id, coalesce(l.jenis, 'barang') as jenis, l.set_id, l.set_komponen, l.deskripsi,
             ps.nama as nama_set, (l.set_id is not null or coalesce(jsonb_typeof(l.set_komponen), '') = 'array') as adalah_set
        from public.po_lines l left join public.product_sets ps on ps.id = l.set_id
       where l.po_id = s.po_id
       order by l.urut, l.id
    loop
      if not pl.adalah_set then
        kk := pos; acc := 0;
        while kk <= n and acc < pl.qty and a_prod[kk] is not distinct from pl.product_id
              and coalesce(a_jenis[kk], 'barang') = pl.jenis loop
          acc := acc + a_qty[kk]; kk := kk + 1;
        end loop;
        if kk > pos and acc = pl.qty then pos := kk; end if;   -- tidak di posisi ini → dilewati, posisi tetap
        continue;
      end if;

      if not (pl.qty > 0 and pl.qty = trunc(pl.qty)) then exit; end if;
      -- komponen = snapshot saat PO disimpan; data lama tanpa snapshot → definisi set kini (= poKomponenSet di layar)
      komp := case when jsonb_typeof(pl.set_komponen) = 'array' then pl.set_komponen
                   else (select jsonb_agg(jsonb_build_object('product_id', c2.product_id, 'qty', c2.qty, 'urut', c2.urut)
                                          order by c2.urut, c2.id)
                           from public.product_set_components c2 where c2.set_id = pl.set_id) end;
      if komp is null or jsonb_array_length(komp) = 0 then exit; end if;
      select jsonb_agg(t.v order by coalesce(nullif(t.v->>'urut', '')::numeric, 0), t.o) into komp
        from jsonb_array_elements(komp) with ordinality t(v, o);

      kk := pos; cocok := true; tanda := '{}'; isi_tanda := '{}';
      for c in select (t.v->>'product_id')::bigint pid, (t.v->>'qty')::numeric q,
                      (select sum((t2.v->>'qty')::numeric) from jsonb_array_elements(komp) t2(v)
                        where t2.v->>'product_id' = t.v->>'product_id') isi
                 from jsonb_array_elements(komp) with ordinality t(v, o) order by t.o
      loop
        perlu := pl.qty * c.q; acc := 0;
        while kk <= n and acc < perlu and a_prod[kk] is not distinct from c.pid and coalesce(a_jenis[kk], 'barang') <> 'biaya' loop
          acc := acc + a_qty[kk];
          tanda := tanda || a_id[kk]; isi_tanda := isi_tanda || c.isi;
          kk := kk + 1;
        end loop;
        if acc <> perlu or not (c.isi > 0) then cocok := false; exit; end if;
      end loop;
      if not cocok then exit; end if;   -- ragu = berhenti: set ini dan sesudahnya tidak ditandai

      g := g + 1;
      update public.sales_order_lines x
         set set_grup = g,
             set_nama = left(coalesce(nullif(btrim(pl.deskripsi), ''), nullif(btrim(pl.nama_set), ''), 'Set'), 200),
             set_qty  = pl.qty,
             set_isi  = m.isi
        from unnest(tanda, isi_tanda) m(id, isi)
       where x.id = m.id;
      n_set := n_set + 1;
      pos := kk;
    end loop;

    if g > 0 then
      update public.usul_ubah u
         set nilai_lama = jsonb_set(u.nilai_lama, '{baris}', (
               select coalesce(jsonb_agg(case when coalesce(e.v->>'set_grup', '') <> '' then e.v
                                              else e.v || coalesce((select jsonb_build_object('set_grup', x.set_grup, 'set_nama', x.set_nama,
                                                                                              'set_qty', x.set_qty, 'set_isi', x.set_isi)
                                                                      from public.sales_order_lines x
                                                                     where x.so_id = s.id and x.id::text = e.v->>'id'), '{}'::jsonb) end
                                         order by e.o), '[]'::jsonb)
                 from jsonb_array_elements(u.nilai_lama->'baris') with ordinality e(v, o)))
       where u.jenis = 'sp' and u.ref_id = s.id and u.status = 'menunggu'
         and jsonb_typeof(u.nilai_lama->'baris') = 'array';
    end if;
  end loop;
  set local session_replication_role = origin;
  return n_set;
end $function$;
