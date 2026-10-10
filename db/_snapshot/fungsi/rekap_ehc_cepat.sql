CREATE OR REPLACE FUNCTION public.rekap_ehc_cepat()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_hari date := public.hari_ini_wib(); v_ids bigint[]; v_n integer; v_total numeric(14,2) := 0;
        v_batch bigint; v_lewat integer; v_upd integer;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh menandai pencairan cepat.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('rhj.rekap_ehc'));
  perform 1 from public.ehc_klaim k
   where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null
   order by k.id for update;
  perform 1 from public.sales_orders s
   where s.id in (select a.so_id from public.ehc_klaim_alokasi a join public.ehc_klaim k on k.id = a.klaim_id
                   where a.nominal > 0 and k.status = 'disetujui' and k.cepat_minta and k.cepat_ok
                     and k.transfer_batch_id is null)
   order by s.id for share;
  select array_agg(k.id order by k.id) into v_ids from public.ehc_klaim k
   where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null
     and exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id)
     and public.klaim_ehc_terkunci_pengajuan(k.id) is null
     and not exists (select 1 from public.ehc_klaim_alokasi a join public.sales_orders s on s.id = a.so_id
                      where a.klaim_id = k.id and a.nominal > 0 and s.batal);
  v_n := coalesce(array_length(v_ids, 1), 0);
  select count(*) into v_lewat from public.ehc_klaim k
   where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null
     and k.id <> all(coalesce(v_ids, '{}'::bigint[]));
  if v_n = 0 then
    return jsonb_build_object('batch', null, 'jumlah', 0, 'total', 0, 'dilewati', v_lewat,
      'pesan', case when v_lewat > 0
        then 'Tidak ada klaim cepat yang bisa ditandai: ' || v_lewat || ' klaim yang sudah disetujui GM '
          || 'belum punya rekening tujuan terkunci atau SP-nya batal.'
        else 'Belum ada klaim EHC yang disetujui GM untuk dicairkan cepat. Tidak ada batch '
          || 'baru yang dibuat.' end);
  end if;
  select coalesce(sum(n.nominal), 0) into v_total from public.ehc_klaim_nilai n where n.klaim_id = any(v_ids);
  insert into public.transfer_batch (jenis, bulan, tanggal, jumlah_klaim, total, cepat, dibuat_oleh)
  values ('ehc', to_char(v_hari, 'YYYY-MM'), v_hari, v_n, v_total, true, auth.uid())
  returning id into v_batch;
  perform set_config('rhj.batch', 'on', true);
  update public.ehc_klaim set transfer_batch_id = v_batch
   where id = any(v_ids) and transfer_batch_id is null and status = 'disetujui';
  get diagnostics v_upd = row_count;
  perform set_config('rhj.batch', 'off', true);
  if v_upd <> v_n then
    raise exception 'Daftar klaim EHC cepat berubah saat dikunci (% dari %) — ulangi.', v_upd, v_n using errcode = '40001';
  end if;
  return jsonb_build_object('batch', v_batch, 'jumlah', v_n, 'total', v_total, 'dilewati', v_lewat,
    'pesan', v_n || ' klaim EHC cepat masuk batch #' || v_batch || ' (total ' || public.rp_teks(v_total)
          || '). Transfer sesuai daftar; yang gagal keluarkan; lalu isi nomor referensinya.'
          || case when v_lewat > 0
               then ' ' || v_lewat || ' klaim lain dilewati (tanpa rekening terkunci atau SP batal).'
               else '' end);
end $function$;
