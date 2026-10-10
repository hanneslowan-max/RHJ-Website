CREATE OR REPLACE FUNCTION public.rekap_ehc_bulanan(p_bulan text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_hari date := public.hari_ini_wib(); v_ids bigint[]; v_n integer; v_total numeric(14,2) := 0;
        v_batch bigint; v_ada bigint; v_upd integer; v_ml integer; v_mg integer; v_tr integer;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengunci daftar bayar EHC.' using errcode = '42501';
  end if;
  if p_bulan is null or p_bulan !~ '^\d{4}-\d{2}$' then
    raise exception 'Periode harus dalam bentuk YYYY-MM.' using errcode = '22023';
  end if;
  if p_bulan <> public.periode_bayar_ehc(v_hari) then
    raise exception 'Yang bisa dikunci hari ini periode % (periode berikutnya mulai tgl 20). Periode lama yang tertunda ikut otomatis.',
      public.periode_bayar_ehc(v_hari) using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('rhj.rekap_ehc'));
  select b.id into v_ada from public.transfer_batch b
   where b.jenis = 'ehc' and b.periode_bayar = p_bulan and not b.cepat and b.jumlah_klaim > 0
   order by b.id limit 1;
  if v_ada is not null then
    raise exception 'Daftar bayar EHC periode % sudah dikunci (batch #%).', p_bulan, v_ada using errcode = '22023';
  end if;

  perform 1 from public.ehc_klaim k
   where k.id in (select public.ehc_klaim_siap_transfer(p_bulan)) order by k.id for update;
  perform 1 from public.sales_orders s
   where s.id in (select a.so_id from public.ehc_klaim_alokasi a
                   where a.nominal > 0 and a.klaim_id in (select public.ehc_klaim_siap_transfer(p_bulan)))
   order by s.id for share;
  select array_agg(x order by x) into v_ids from public.ehc_klaim_siap_transfer(p_bulan) x;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n > 0 then
    select coalesce(sum(n.nominal), 0) into v_total from public.ehc_klaim_nilai n where n.klaim_id = any(v_ids);
    insert into public.transfer_batch (jenis, bulan, periode_bayar, tanggal, jumlah_klaim, total, cepat, dibuat_oleh)
    values ('ehc', p_bulan, p_bulan, v_hari, v_n, v_total, false, auth.uid())
    returning id into v_batch;
    perform set_config('rhj.batch', 'on', true);
    update public.ehc_klaim set transfer_batch_id = v_batch
     where id = any(v_ids) and transfer_batch_id is null and status = 'disetujui';
    get diagnostics v_upd = row_count;
    perform set_config('rhj.batch', 'off', true);
    if v_upd <> v_n then
      raise exception 'Daftar klaim EHC berubah saat dikunci (% dari %) — ulangi.', v_upd, v_n using errcode = '40001';
    end if;
  end if;

  select count(*) filter (where s.x = 'menunggu_lunas'), count(*) filter (where s.x = 'menunggu_gm'),
         count(*) filter (where s.x = 'tanpa_rekening')
    into v_ml, v_mg, v_tr
    from (select public.ehc_keadaan_bayar(k, p_bulan) as x from public.ehc_klaim k
           where k.transfer_batch_id is null and k.status in ('diajukan','disetujui')) s;
  return jsonb_build_object('batch', v_batch, 'jumlah', v_n, 'total', v_total,
    'menunggu_lunas', v_ml, 'menunggu_gm', v_mg, 'tanpa_rekening', v_tr,
    'pesan', case when v_n = 0
      then 'Tidak ada klaim EHC yang siap dibayar untuk periode ' || p_bulan || '. Tidak ada batch yang dibuat.'
      else v_n || ' klaim EHC (' || public.rp_teks(v_total) || ') dikunci di batch #' || v_batch
           || '. Transfer sesuai daftar; yang gagal keluarkan; lalu isi referensi.' end);
end $function$;
