CREATE OR REPLACE FUNCTION public.rekap_transfer(p_jenis text, p_bulan text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_batch bigint; v_n integer; v_total numeric(14,2); v_pj public.transfer_pengajuan;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh merekap transfer.'
      using errcode = '42501';
  end if;
  if p_jenis not in ('ehc','komisi') then
    raise exception 'Jenis rekap harus ehc atau komisi.';
  end if;
  if p_bulan !~ '^\d{4}-\d{2}$' then
    raise exception 'Bulan harus dalam bentuk YYYY-MM.';
  end if;

  select * into v_pj from public.transfer_pengajuan
   where jenis = p_jenis and bulan = p_bulan and status = 'disetujui';
  if not found then
    raise exception
      'Belum ada persetujuan GM untuk % bulan %. Tekan "Minta persetujuan GM" dulu; '
      'sesudah GM menyetujuinya, barulah pembayaran boleh ditandai.', p_jenis, p_bulan
      using errcode = '42501';
  end if;

  insert into public.transfer_batch (jenis, bulan, dibuat_oleh)
  values (p_jenis, p_bulan, auth.uid())
  returning id into v_batch;

  if p_jenis = 'ehc' then
    with kena as (
      update public.ehc_klaim k set transfer_batch_id = v_batch
       where k.transfer_batch_id is null
         and k.id in (select b.klaim_id from public.transfer_pengajuan_baris b
                       where b.pengajuan_id = v_pj.id)
      returning k.id)
    select count(*) into v_n from kena;
    select coalesce(sum(n.nominal), 0) into v_total
      from public.ehc_klaim k join public.ehc_klaim_nilai n on n.klaim_id = k.id
     where k.transfer_batch_id = v_batch;
  else
    with kena as (
      update public.komisi_klaim k set transfer_batch_id = v_batch
       where k.transfer_batch_id is null
         and k.id in (select b.klaim_id from public.transfer_pengajuan_baris b
                       where b.pengajuan_id = v_pj.id)
      returning k.id)
    select count(*) into v_n from kena;
    select coalesce(sum(n.nominal), 0) into v_total
      from public.komisi_klaim k join public.komisi_klaim_nilai n on n.klaim_id = k.id
     where k.transfer_batch_id = v_batch;
  end if;

  if v_n = 0 then
    delete from public.transfer_batch where id = v_batch;
    return jsonb_build_object('batch', null, 'jumlah', 0, 'total', 0,
      'pesan', 'Semua klaim di pengajuan #' || v_pj.id || ' ternyata sudah masuk batch lain. '
            || 'Tidak ada batch baru yang dibuat.');
  end if;

  perform set_config('rhj.batch', 'on', true);
  update public.transfer_batch
     set jumlah_klaim = v_n, total = v_total
   where id = v_batch;
  perform set_config('rhj.batch', 'off', true);

  update public.transfer_pengajuan
     set status = 'selesai', transfer_batch_id = v_batch
   where id = v_pj.id;

  return jsonb_build_object('batch', v_batch, 'jumlah', v_n, 'total', v_total,
    'pengajuan', v_pj.id,
    'pesan', v_n || ' klaim ' || p_jenis || ' bulan ' || p_bulan
          || ' masuk batch #' || v_batch || ' (persetujuan GM #' || v_pj.id
          || '). Isi nomor referensi transfernya supaya pembayaran ini bisa ditelusuri nanti.');
end $function$;
