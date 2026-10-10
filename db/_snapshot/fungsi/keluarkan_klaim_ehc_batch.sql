CREATE OR REPLACE FUNCTION public.keluarkan_klaim_ehc_batch(p_klaim bigint, p_alasan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim; b public.transfer_batch; v_batch bigint; v_nom numeric(14,2);
        v_alasan text := nullif(btrim(coalesce(p_alasan, '')), '');
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengeluarkan klaim dari batch.' using errcode = '42501';
  end if;
  if v_alasan is null then
    raise exception 'Alasan wajib diisi (mis. transfer gagal, rekening tidak aktif).' using errcode = '22023';
  end if;
  select transfer_batch_id into v_batch from public.ehc_klaim where id = p_klaim;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if v_batch is null then
    raise exception 'Klaim EHC #% tidak sedang di batch transfer.', p_klaim using errcode = '22023';
  end if;
  select * into b from public.transfer_batch where id = v_batch for update;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if k.transfer_batch_id is distinct from b.id then
    raise exception 'Klaim EHC #% berubah — muat ulang.', p_klaim using errcode = '40001';
  end if;
  if b.jenis <> 'ehc' then
    raise exception 'Batch #% bukan batch EHC.', b.id using errcode = '22023';
  end if;
  if b.no_referensi is not null then
    raise exception 'Batch #% sudah berreferensi — uang dianggap keluar; klaim tidak bisa dikeluarkan.', b.id
      using errcode = '22023';
  end if;
  select n.nominal into v_nom from public.ehc_klaim_nilai n where n.klaim_id = p_klaim;
  perform set_config('rhj.batch', 'on', true);
  update public.ehc_klaim set transfer_batch_id = null where id = p_klaim;
  update public.transfer_batch set jumlah_klaim = jumlah_klaim - 1, total = total - coalesce(v_nom, 0) where id = b.id;
  perform set_config('rhj.batch', 'off', true);
  insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh)
  values (p_klaim, 'bayar', 'keluar_batch', v_alasan,
          jsonb_build_object('batch', b.id, 'cepat', b.cepat, 'nominal', v_nom), auth.uid());
  return 'Klaim EHC #' || p_klaim || ' dikeluarkan dari batch #' || b.id || '. '
      || case when b.cepat then 'Klaim kembali ke daftar EHC emergency.'
              else 'Klaim tetap disetujui dan ikut daftar bayar tgl 20 berikutnya.' end;
end $function$;
