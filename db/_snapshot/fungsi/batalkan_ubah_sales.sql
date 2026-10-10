CREATE OR REPLACE FUNCTION public.batalkan_ubah_sales(p_batch bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.ubah_sales_batch; t text; v_n bigint; v_total bigint := 0; v_lewat bigint := 0;
begin
  if not public.boleh_ubah_master_sales() then
    raise exception 'Pembatalan hanya untuk owner atau GM.' using errcode = '42501';
  end if;
  select * into b from public.ubah_sales_batch where id = p_batch;
  if not found then
    raise exception 'Batch #% tidak ada.', p_batch using errcode = 'P0002';
  end if;

  -- Daftar putih. Nama tabel datang dari baris jejak — yang kita tulis
  -- sendiri — tapi tetap tidak dipakai apa adanya: baris jejak adalah
  -- DATA, dan data tidak boleh berubah jadi perintah.
  foreach t in array array['customers','leads','purchase_orders','sales_orders',
                           'ehc_klaim','komisi_klaim','sales_rep_rekening'] loop
    execute format(
      'with sasaran as (
         select baris_id, rep_lama from public.ubah_sales_baris
          where batch_id = $1 and tabel = $2)
       update public.%I x set sales_rep_id = s.rep_lama
         from sasaran s
        where x.%s = s.baris_id
          and x.sales_rep_id is not distinct from
              (select rep_baru from public.ubah_sales_baris
                where batch_id = $1 and tabel = $2 and baris_id = s.baris_id)',
      t, case when t = 'sales_rep_rekening' then 'sales_rep_id' else 'id' end)
      using p_batch, t;
    get diagnostics v_n = row_count;
    v_total := v_total + v_n;
    execute format('select count(*) from public.ubah_sales_baris where batch_id = $1 and tabel = $2')
      into v_n using p_batch, t;
    v_lewat := v_lewat + v_n;
  end loop;
  v_lewat := v_lewat - v_total;

  -- Status aktif & tautan akun dikembalikan paling akhir: kalau
  -- dikembalikan lebih dulu, baris yang dipulihkan di atas sempat
  -- menunjuk ke sales yang aktifnya belum pulih.
  update public.sales_reps r set aktif = j.aktif_lama
    from public.ubah_sales_baris j
   where j.batch_id = p_batch and j.tabel = 'sales_reps' and r.id = j.baris_id
     and j.aktif_lama is not null;

  delete from public.ubah_sales_batch where id = p_batch;
  return format('Batch #%s (%s) dibatalkan: %s baris dikembalikan, %s dilewati karena '
                'sudah diubah sesudahnya. Tautan akun ke nama sales TIDAK dikembalikan '
                'otomatis — isi ulang lewat tab Pengguna kalau perlu.',
                p_batch, b.jenis, v_total, greatest(v_lewat, 0));
end $function$;
