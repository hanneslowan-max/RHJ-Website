CREATE OR REPLACE FUNCTION public.pensiunkan_sales(p_nama text[], p_terapkan boolean DEFAULT false)
 RETURNS TABLE(putusan text, keterangan text, jumlah bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_batch bigint; n text; v_id bigint;
  v_pel bigint; v_lead bigint; v_total bigint := 0;
begin
  if not public.boleh_ubah_master_sales() then
    raise exception 'Menonaktifkan sales hanya untuk owner atau GM.'
      using errcode = '42501';
  end if;
  if p_nama is null or array_length(p_nama, 1) is null then
    raise exception 'Daftar nama kosong.' using errcode = '22023';
  end if;

  -- Seluruh nama diperiksa DULU. Kalau satu nama salah ketik, tidak ada
  -- satu pun yang dikerjakan — setengah pensiun lebih sulit dibereskan
  -- daripada tidak dikerjakan sama sekali.
  foreach n in array p_nama loop
    if public.sales_id_dari_nama(n) is null then
      return query select 'BATAL'::text,
        format('Nama "%s" tidak ada di master, atau ada lebih dari satu yang cocok. '
               'Tidak ada satu pun yang diubah.', n)::text, 0::bigint;
      return;
    end if;
  end loop;

  if p_terapkan then
    insert into public.ubah_sales_batch (jenis, oleh, catatan)
    values ('pensiun', auth.uid(), array_to_string(p_nama, ', '))
    returning id into v_batch;
  end if;

  foreach n in array p_nama loop
    v_id := public.sales_id_dari_nama(n);
    select count(*) into v_pel  from public.customers where sales_rep_id = v_id;
    select count(*) into v_lead from public.leads     where sales_rep_id = v_id;

    if p_terapkan then
      insert into public.ubah_sales_baris (batch_id, tabel, baris_id, rep_lama, rep_baru)
      select v_batch, 'customers', id, v_id, null from public.customers where sales_rep_id = v_id;
      update public.customers set sales_rep_id = null where sales_rep_id = v_id;

      insert into public.ubah_sales_baris (batch_id, tabel, baris_id, rep_lama, rep_baru)
      select v_batch, 'leads', id, v_id, null from public.leads where sales_rep_id = v_id;
      update public.leads set sales_rep_id = null where sales_rep_id = v_id;

      insert into public.ubah_sales_baris (batch_id, tabel, baris_id, aktif_lama, aktif_baru)
      select v_batch, 'sales_reps', id, aktif, false from public.sales_reps where id = v_id;
      update public.sales_reps set aktif = false where id = v_id;
      -- Tautan akunnya ikut dilepas: akun yang masih menunjuk nama yang
      -- sudah keluar tetap bisa login sebagai orang itu.
      insert into public.ubah_sales_baris (batch_id, tabel, baris_id, rep_lama, rep_baru)
      select v_batch, 'akun', id, v_id, null
        from public.sales_reps where id = v_id and profile_id is not null;
      update public.sales_reps set profile_id = null where id = v_id;
    end if;

    v_total := v_total + v_pel + v_lead;
    return query select
      (case when p_terapkan then 'dinonaktifkan' else 'akan dinonaktifkan' end)::text,
      format('%s — %s pelanggan & %s lead dikosongkan; riwayat PO/SP/komisinya tetap atas namanya',
             (select nama from public.sales_reps where id = v_id), v_pel, v_lead)::text,
      (v_pel + v_lead)::bigint;
  end loop;

  if p_terapkan then
    update public.ubah_sales_batch set jumlah = v_total where id = v_batch;
    return query select 'DITERAPKAN'::text,
      format('batch #%s — bisa dibatalkan dengan batalkan_ubah_sales(%s)', v_batch, v_batch)::text,
      v_total;
  else
    return query select 'UJI COBA'::text,
      'Belum ada yang diubah. Jalankan pensiunkan_sales(ARRAY[…], true) untuk menerapkan.'::text,
      v_total;
  end if;
end $function$;
