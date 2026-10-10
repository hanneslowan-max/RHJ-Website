CREATE OR REPLACE FUNCTION public.beku_harga_list_baris()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tgl date; v_dibuat timestamptz; v_lama jsonb; x jsonb;
begin
  if tg_op = 'UPDATE' and new.product_id is not distinct from old.product_id then
    new.harga_list := old.harga_list;
    return new;
  end if;
  select so.tanggal, so.dibuat_pada into v_tgl, v_dibuat from public.sales_orders so where so.id = new.so_id;
  if not found then return new; end if;
  new.harga_list := case when new.product_id is null then null
                         else public.harga_list_pada(new.product_id, v_tgl, v_dibuat) end;
  if tg_op = 'INSERT' and new.product_id is not null
     and coalesce(current_setting('rhj.usul', true), '') = 'on' then
    select u.nilai_lama -> 'baris' into v_lama
      from public.usul_ubah u
     where u.jenis = 'sp' and u.ref_id = new.so_id and u.status = 'menunggu';
    if jsonb_typeof(v_lama) = 'array' then
      select e.v into x
        from jsonb_array_elements(v_lama) with ordinality e(v, o)
       where nullif(e.v->>'product_id', '') = new.product_id::text
         and e.v ? 'harga_list'
       order by (e.v->>'urut' = new.urut::text) desc, e.o
       limit 1;
      if x is not null then
        new.harga_list := case when coalesce(x->>'harga_list', '') ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$'
                               then (x->>'harga_list')::numeric end;
      end if;
    end if;
  end if;
  return new;
end $function$;
