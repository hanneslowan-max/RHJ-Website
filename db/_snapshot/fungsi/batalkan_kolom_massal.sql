CREATE OR REPLACE FUNCTION public.batalkan_kolom_massal(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b record; kol text; tipe text; n int; dilewati int;
begin
  select * into b from public.edit_massal where id = p_id;
  if b.id is null then
    raise exception 'Edit massal #% tidak ditemukan.', p_id using errcode = 'P0002';
  end if;
  if b.dibatalkan_pada is not null then
    raise exception 'Edit massal #% sudah dibatalkan pada %.', p_id, b.dibatalkan_pada
      using errcode = '22023';
  end if;
  kol := public.kolom_massal(b.jenis);
  if kol is null then
    raise exception 'Edit massal #% bukan perubahan kolom produk.', p_id using errcode = '22023';
  end if;
  if not (public.setara_owner() or b.dibuat_oleh = auth.uid()) then
    raise exception 'Hanya owner, GM, atau orang yang menerapkannya yang boleh membatalkan.'
      using errcode = '42501';
  end if;
  if not public.boleh_massal(b.jenis) then
    raise exception 'Anda tidak berwenang mengubah kolom % secara massal.', b.jenis
      using errcode = '42501';
  end if;

  select format_type(a.atttypid, a.atttypmod) into tipe
    from pg_attribute a
   where a.attrelid = 'public.products'::regclass and a.attname = kol;

  execute format(
    'update public.products p set %1$I = n.lama::%2$s
       from public.edit_massal_nilai n
      where n.batch_id = $1 and n.product_id = p.id
        and p.%1$I::text is not distinct from n.baru', kol, tipe)
    using p_id;
  get diagnostics n = row_count;

  select count(*) - n into dilewati
    from public.edit_massal_nilai where batch_id = p_id;

  update public.edit_massal
     set dibatalkan_pada = now(), dibatalkan_oleh = auth.uid()
   where id = p_id;

  return n || ' produk dikembalikan'
         || case when dilewati > 0
                 then '. ' || dilewati || ' dilewati karena sudah diubah lagi sesudah itu.'
                 else '.' end;
end $function$;
