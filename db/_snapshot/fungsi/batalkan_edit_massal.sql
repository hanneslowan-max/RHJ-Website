CREATE OR REPLACE FUNCTION public.batalkan_edit_massal(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b record; n int; n_kembali int := 0;
begin
  select * into b from public.edit_massal where id = p_id;
  if b.id is null then
    raise exception 'Edit massal #% tidak ditemukan.', p_id using errcode = 'P0002';
  end if;
  if b.dibatalkan_pada is not null then
    raise exception 'Edit massal #% sudah dibatalkan pada %.', p_id, b.dibatalkan_pada
      using errcode = '22023';
  end if;
  if not (public.setara_owner() or b.dibuat_oleh = auth.uid()) then
    raise exception 'Hanya owner, GM, atau orang yang menerapkannya yang boleh membatalkan.'
      using errcode = '42501';
  end if;
  if not public.boleh_massal(b.jenis) then
    raise exception 'Anda tidak berwenang mengubah % secara massal.',
      case b.jenis when 'harga' then 'harga jual' else 'HPP' end using errcode = '42501';
  end if;

  -- Kembalikan DULU. Sesudah dikembalikan, batch_id-nya ikut kembali ke
  -- pemilik lamanya, jadi delete di bawah tidak menyentuhnya lagi.
  if b.jenis = 'harga' then
    update public.price_list pl
       set harga = t.nilai_lama, catatan = t.catatan_lama,
           batch_id = t.batch_lama, dibuat_oleh = t.dibuat_oleh_lama,
           dibuat_pada = coalesce(t.dibuat_pada_lama, pl.dibuat_pada)
      from public.edit_massal_timpa t
     where t.batch_id = p_id and t.jenis = 'harga'
       and pl.product_id = t.product_id and pl.berlaku_dari = t.berlaku_dari;
    get diagnostics n_kembali = row_count;
    delete from public.price_list where batch_id = p_id;
    get diagnostics n = row_count;
  else
    update public.product_costs pc
       set hpp = t.nilai_lama, catatan = t.catatan_lama, sumber = t.sumber_lama,
           batch_id = t.batch_lama, dibuat_oleh = t.dibuat_oleh_lama,
           dibuat_pada = coalesce(t.dibuat_pada_lama, pc.dibuat_pada)
      from public.edit_massal_timpa t
     where t.batch_id = p_id and t.jenis = 'hpp'
       and pc.product_id = t.product_id and pc.berlaku_dari = t.berlaku_dari;
    get diagnostics n_kembali = row_count;
    delete from public.product_costs where batch_id = p_id;
    get diagnostics n = row_count;
  end if;

  delete from public.edit_massal_timpa where batch_id = p_id;

  update public.edit_massal
     set dibatalkan_pada = now(), dibatalkan_oleh = auth.uid()
   where id = p_id;

  return n || ' baris ' || case b.jenis when 'harga' then 'harga' else 'HPP' end
         || ' dihapus'
         || case when n_kembali > 0
                 then ', ' || n_kembali || ' baris dikembalikan ke nilai sebelumnya'
                 else '' end
         || '. Nilai sebelumnya berlaku lagi.';
end $function$;
