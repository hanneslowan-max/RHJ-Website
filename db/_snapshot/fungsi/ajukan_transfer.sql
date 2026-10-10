CREATE OR REPLACE FUNCTION public.ajukan_transfer(p_jenis text, p_bulan text, p_catatan text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_n integer; v_total numeric(14,2); v_lama public.transfer_pengajuan;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengajukan transfer.'
      using errcode = '42501';
  end if;
  if p_jenis not in ('ehc','komisi') then
    raise exception 'Jenis harus ehc atau komisi.' using errcode = '22023';
  end if;
  if p_bulan !~ '^\d{4}-\d{2}$' then
    raise exception 'Bulan harus dalam bentuk YYYY-MM.' using errcode = '22023';
  end if;
  if p_jenis = 'ehc' then
    raise exception 'Pembayaran EHC tidak lagi lewat pengajuan transfer (berkas 141): GM memeriksa per klaim sesudah tgl 18, finance mengunci daftar bayar mulai tgl 20 (rekap_ehc_bulanan).'
      using errcode = '0A000';
  end if;

  select * into v_lama from public.transfer_pengajuan
   where jenis = p_jenis and bulan = p_bulan and status in ('menunggu','disetujui');
  if found then
    return jsonb_build_object('pengajuan', v_lama.id, 'status', v_lama.status,
      'jumlah', v_lama.jumlah_klaim, 'total', v_lama.total,
      'pesan', case when v_lama.status = 'menunggu'
                 then 'Pengajuan #' || v_lama.id || ' untuk ' || p_jenis || ' bulan ' || p_bulan
                      || ' sudah ada dan masih menunggu GM. Tidak ada pengajuan baru yang dibuat.'
                 else 'Pengajuan #' || v_lama.id || ' untuk ' || p_jenis || ' bulan ' || p_bulan
                      || ' SUDAH DISETUJUI GM. Silakan transfer, lalu tandai sudah ditransfer.'
               end);
  end if;

  if p_jenis = 'ehc' then
    select count(*) into v_n from public.ehc_klaim_siap_transfer(p_bulan);
  else
    select count(*) into v_n from public.komisi_klaim k
     where k.transfer_batch_id is null and to_char(k.tanggal, 'YYYY-MM') = p_bulan;
  end if;
  if v_n = 0 then
    return jsonb_build_object('pengajuan', null, 'jumlah', 0, 'total', 0,
      'pesan', 'Tidak ada klaim ' || p_jenis || ' bulan ' || p_bulan
            || ' yang siap ditransfer. Tidak ada yang perlu disetujui.');
  end if;

  insert into public.transfer_pengajuan (jenis, bulan, catatan, diajukan_oleh)
  values (p_jenis, p_bulan, nullif(btrim(coalesce(p_catatan,'')), ''), auth.uid())
  returning id into v_id;

  -- Daftarnya DIKUNCI di sini. Klaim yang masuk sesudah ini menunggu
  -- pengajuan berikutnya.
  if p_jenis = 'ehc' then
    insert into public.transfer_pengajuan_baris (pengajuan_id, klaim_id)
    select v_id, x from public.ehc_klaim_siap_transfer(p_bulan) x;
    select count(*), coalesce(sum(n.nominal), 0) into v_n, v_total
      from public.transfer_pengajuan_baris b
      join public.ehc_klaim_nilai n on n.klaim_id = b.klaim_id
     where b.pengajuan_id = v_id;
  else
    insert into public.transfer_pengajuan_baris (pengajuan_id, klaim_id)
    select v_id, k.id from public.komisi_klaim k
     where k.transfer_batch_id is null and to_char(k.tanggal, 'YYYY-MM') = p_bulan;
    select count(*), coalesce(sum(n.nominal), 0) into v_n, v_total
      from public.transfer_pengajuan_baris b
      join public.komisi_klaim_nilai n on n.klaim_id = b.klaim_id
     where b.pengajuan_id = v_id;
  end if;

  update public.transfer_pengajuan
     set jumlah_klaim = v_n, total = v_total where id = v_id;

  return jsonb_build_object('pengajuan', v_id, 'status', 'menunggu',
    'jumlah', v_n, 'total', v_total,
    'pesan', v_n || ' klaim ' || p_jenis || ' bulan ' || p_bulan
          || ' diajukan ke GM sebagai pengajuan #' || v_id
          || '. Daftarnya sudah dikunci — klaim yang masuk sesudah ini menunggu '
          || 'pengajuan berikutnya.');
end $function$;
