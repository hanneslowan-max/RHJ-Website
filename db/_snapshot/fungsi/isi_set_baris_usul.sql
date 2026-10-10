CREATE OR REPLACE FUNCTION public.isi_set_baris_usul()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_baru jsonb; v_lama jsonb; x jsonb;
begin
  if coalesce(current_setting('rhj.usul', true), '') <> 'on' or new.set_grup is not null then
    return new;
  end if;
  select u.nilai_baru -> 'baris', u.nilai_lama -> 'baris' into v_baru, v_lama
    from public.usul_ubah u
   where u.jenis = 'sp' and u.ref_id = new.so_id and u.status = 'menunggu';
  if v_baru is null or jsonb_typeof(v_baru) <> 'array' then return new; end if;

  select e.v into x
    from jsonb_array_elements(v_baru) with ordinality e(v, o)
   where e.v->>'urut' = new.urut::text
     and nullif(e.v->>'product_id', '') is not distinct from new.product_id::text
   order by e.o limit 1;
  if x is null then return new; end if;
  if not (x ? 'set_grup') then
    x := null;
    if jsonb_typeof(v_lama) = 'array' then
      select e.v into x
        from jsonb_array_elements(v_lama) with ordinality e(v, o)
       where e.v->>'urut' = new.urut::text
         and nullif(e.v->>'product_id', '') is not distinct from new.product_id::text
       order by e.o limit 1;
    end if;
    if x is null then return new; end if;
  end if;

  if coalesce(new.jenis, 'barang') <> 'biaya'
     and coalesce(x->>'set_grup', '') ~ '^[1-9][0-9]{0,3}$'
     and coalesce(x->>'set_qty', '')  ~ '^[1-9][0-9]{0,9}(\.0+)?$'
     and coalesce(x->>'set_isi', '')  ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$'
     and coalesce(x->>'set_isi', '')  !~ '^0+(\.0+)?$' then
    new.set_grup := (x->>'set_grup')::smallint;
    new.set_nama := left(nullif(btrim(x->>'set_nama'), ''), 200);
    new.set_qty  := (x->>'set_qty')::numeric;
    new.set_isi  := (x->>'set_isi')::numeric;
  end if;
  return new;
end $function$;
