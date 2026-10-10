CREATE OR REPLACE FUNCTION public.terapkan_edit_massal(p_jenis text, p_cara text, p_nilai numeric, p_pembulatan integer, p_produk bigint[], p_berlaku date DEFAULT CURRENT_DATE, p_catatan text DEFAULT NULL::text, p_sumber text DEFAULT NULL::text, p_tempel jsonb DEFAULT NULL::jsonb, p_paksa boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n_lonjakan int; n_bawah int; n_ubah int; b_id bigint;
begin
  if p_jenis not in ('harga','hpp') then
    raise exception 'Jenis edit massal harus harga atau hpp.' using errcode = '22023';
  end if;
  if not public.boleh_massal(p_jenis) then
    raise exception 'Anda tidak berwenang mengubah % secara massal.',
      case p_jenis when 'harga' then 'harga jual' else 'HPP' end using errcode = '42501';
  end if;

  select count(*) filter (where tanda = 'lonjakan'),
         count(*) filter (where tanda = 'di_bawah_hpp'),
         count(*) filter (where tanda in ('ok','baru','lonjakan','di_bawah_hpp'))
    into n_lonjakan, n_bawah, n_ubah
    from public.hitung_edit_massal(p_jenis, p_cara, p_nilai, p_pembulatan, p_produk, p_tempel);

  if not p_paksa and (n_lonjakan > 0 or n_bawah > 0) then
    raise exception 'Ditahan: % baris berubah lebih dari 50%%, % baris jadi di bawah HPP. Periksa lagi, atau minta owner menerapkannya dengan paksa.',
      n_lonjakan, n_bawah using errcode = '23514';
  end if;

  if p_paksa and not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh menerapkan dengan paksa.' using errcode = '42501';
  end if;

  if n_ubah = 0 then
    raise exception 'Tidak ada yang berubah — semua produk terpilih sudah bernilai segitu.'
      using errcode = '22023';
  end if;

  insert into public.edit_massal (jenis, cara, nilai, pembulatan, berlaku_dari,
                                  jumlah_baris, catatan, dipaksa, dibuat_oleh)
  values (p_jenis, p_cara, p_nilai, coalesce(p_pembulatan,0), p_berlaku,
          n_ubah, p_catatan, p_paksa, auth.uid())
  returning id into b_id;

  if p_jenis = 'harga' then
    -- Dicatat SEBELUM ditimpa. Sesudahnya nilai lamanya sudah tidak ada
    -- di mana pun, dan batalkan tidak punya apa-apa untuk dikembalikan.
    insert into public.edit_massal_timpa (batch_id, jenis, product_id, berlaku_dari,
             nilai_lama, catatan_lama, batch_lama, dibuat_oleh_lama, dibuat_pada_lama)
    select b_id, 'harga', pl.product_id, pl.berlaku_dari, pl.harga, pl.catatan,
           pl.batch_id, pl.dibuat_oleh, pl.dibuat_pada
      from public.price_list pl
      join public.hitung_edit_massal(p_jenis, p_cara, p_nilai, p_pembulatan, p_produk, p_tempel) h
        on h.product_id = pl.product_id
     where pl.berlaku_dari = p_berlaku
       and h.tanda in ('ok','baru','lonjakan','di_bawah_hpp');

    insert into public.price_list (product_id, harga, berlaku_dari, catatan, batch_id, dibuat_oleh)
    select product_id, baru, p_berlaku, p_catatan, b_id, auth.uid()
      from public.hitung_edit_massal(p_jenis, p_cara, p_nilai, p_pembulatan, p_produk, p_tempel)
     where tanda in ('ok','baru','lonjakan','di_bawah_hpp')
    on conflict (product_id, berlaku_dari) do update
      set harga = excluded.harga, catatan = excluded.catatan,
          batch_id = excluded.batch_id, dibuat_oleh = excluded.dibuat_oleh;
  else
    insert into public.edit_massal_timpa (batch_id, jenis, product_id, berlaku_dari,
             nilai_lama, catatan_lama, sumber_lama, batch_lama, dibuat_oleh_lama, dibuat_pada_lama)
    select b_id, 'hpp', pc.product_id, pc.berlaku_dari, pc.hpp, pc.catatan, pc.sumber,
           pc.batch_id, pc.dibuat_oleh, pc.dibuat_pada
      from public.product_costs pc
      join public.hitung_edit_massal(p_jenis, p_cara, p_nilai, p_pembulatan, p_produk, p_tempel) h
        on h.product_id = pc.product_id
     where pc.berlaku_dari = p_berlaku
       and h.tanda in ('ok','baru','lonjakan','di_bawah_hpp');

    insert into public.product_costs (product_id, hpp, berlaku_dari, sumber, catatan, batch_id, dibuat_oleh)
    select product_id, baru, p_berlaku, coalesce(p_sumber, 'edit massal'), p_catatan, b_id, auth.uid()
      from public.hitung_edit_massal(p_jenis, p_cara, p_nilai, p_pembulatan, p_produk, p_tempel)
     where tanda in ('ok','baru','lonjakan','di_bawah_hpp')
    on conflict (product_id, berlaku_dari) do update
      set hpp = excluded.hpp, sumber = excluded.sumber, catatan = excluded.catatan,
          batch_id = excluded.batch_id, dibuat_oleh = excluded.dibuat_oleh;
  end if;

  return b_id;
end $function$;
