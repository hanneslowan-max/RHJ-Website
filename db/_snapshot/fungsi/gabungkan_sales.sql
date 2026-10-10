CREATE OR REPLACE FUNCTION public.gabungkan_sales(p_dari text, p_ke text, p_terapkan boolean DEFAULT false)
 RETURNS TABLE(putusan text, keterangan text, jumlah bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_batch bigint; v_dari bigint; v_ke bigint; t text; v_n bigint; v_total bigint := 0;
  v_rek_dari boolean; v_rek_ke boolean; v_profil uuid; v_ke_punya_akun boolean;
begin
  if not public.boleh_ubah_master_sales() then
    raise exception 'Menggabungkan nama sales hanya untuk owner atau GM.'
      using errcode = '42501';
  end if;
  v_dari := public.sales_id_dari_nama(p_dari);
  v_ke   := public.sales_id_dari_nama(p_ke);
  if v_dari is null then
    return query select 'BATAL'::text,
      format('Nama asal "%s" tidak ada di master, atau ada lebih dari satu yang cocok.', p_dari)::text,
      0::bigint; return;
  end if;
  if v_ke is null then
    return query select 'BATAL'::text,
      format('Nama tujuan "%s" tidak ada di master, atau ada lebih dari satu yang cocok.', p_ke)::text,
      0::bigint; return;
  end if;
  if v_dari = v_ke then
    return query select 'BATAL'::text, 'Nama asal dan tujuan sama.'::text, 0::bigint; return;
  end if;

  if p_terapkan then
    insert into public.ubah_sales_batch (jenis, oleh, catatan)
    values ('gabung', auth.uid(), p_dari || ' → ' || p_ke)
    returning id into v_batch;
  end if;

  foreach t in array array['customers','leads','purchase_orders','sales_orders',
                           'ehc_klaim','komisi_klaim'] loop
    execute format('select count(*) from public.%I where sales_rep_id = $1', t)
      into v_n using v_dari;
    if p_terapkan and v_n > 0 then
      execute format(
        'insert into public.ubah_sales_baris (batch_id, tabel, baris_id, rep_lama, rep_baru)
         select $1, $2, id, $3, $4 from public.%I where sales_rep_id = $3', t)
        using v_batch, t, v_dari, v_ke;
      execute format('update public.%I set sales_rep_id = $1 where sales_rep_id = $2', t)
        using v_ke, v_dari;
    end if;
    v_total := v_total + v_n;
    if v_n > 0 then
      return query select
        (case when p_terapkan then 'dipindahkan' else 'akan dipindahkan' end)::text,
        format('%s baris di %s', v_n, t)::text, v_n;
    end if;
  end loop;

  -- Rekening sales: kuncinya sales_rep_id, jadi tidak bisa dipindahkan
  -- kalau tujuannya sudah punya. Yang sudah ada di tujuan DIMENANGKAN —
  -- rekening aktif orang itu lebih mungkin yang terbaru — dan keadaannya
  -- dilaporkan, bukan didiamkan.
  select exists (select 1 from public.sales_rep_rekening where sales_rep_id = v_dari),
         exists (select 1 from public.sales_rep_rekening where sales_rep_id = v_ke)
    into v_rek_dari, v_rek_ke;
  if v_rek_dari and not v_rek_ke then
    if p_terapkan then
      insert into public.ubah_sales_baris (batch_id, tabel, baris_id, rep_lama, rep_baru)
      values (v_batch, 'sales_rep_rekening', v_dari, v_dari, v_ke);
      update public.sales_rep_rekening set sales_rep_id = v_ke where sales_rep_id = v_dari;
    end if;
    return query select (case when p_terapkan then 'dipindahkan' else 'akan dipindahkan' end)::text,
      'rekening sales ikut pindah'::text, 1::bigint;
  elsif v_rek_dari and v_rek_ke then
    return query select 'PERHATIAN'::text,
      format('Dua-duanya punya rekening. Yang dipakai tetap rekening %s; rekening %s '
             'ditinggalkan apa adanya — periksa manual kalau nomornya berbeda.', p_ke, p_dari)::text,
      0::bigint;
  end if;

  if p_terapkan then
    -- Tujuan diaktifkan: orangnya masih bekerja, dan nama yang dipakai
    -- ke depan adalah nama tujuan.
    insert into public.ubah_sales_baris (batch_id, tabel, baris_id, aktif_lama, aktif_baru)
    select v_batch, 'sales_reps', id, aktif, true from public.sales_reps where id = v_ke;
    update public.sales_reps set aktif = true where id = v_ke;

    insert into public.ubah_sales_baris (batch_id, tabel, baris_id, aktif_lama, aktif_baru)
    select v_batch, 'sales_reps', id, aktif, false from public.sales_reps where id = v_dari;

    -- Tautan akunnya pindah kalau tujuannya belum punya: orang yang sama
    -- tidak boleh kehilangan cara masuknya hanya karena namanya diganti.
    --
    -- URUTANNYA PENTING, dan ini ketahuan dari uji: profile_id punya
    -- indeks unik (sales_reps_profil_uniq). Kalau tujuannya diisi lebih
    -- dulu sementara asalnya masih memegang uid yang sama, insertnya
    -- ditolak "duplicate key" — jadi asalnya harus dilepas DULU.
    select profile_id into v_profil from public.sales_reps where id = v_dari;
    select exists (select 1 from public.sales_reps where id = v_ke and profile_id is not null)
      into v_ke_punya_akun;
    update public.sales_reps set aktif = false, profile_id = null where id = v_dari;
    if v_profil is not null and not v_ke_punya_akun then
      insert into public.ubah_sales_baris (batch_id, tabel, baris_id, rep_lama, rep_baru)
      values (v_batch, 'akun_pindah', v_ke, v_dari, v_ke);
      update public.sales_reps set profile_id = v_profil where id = v_ke;
    end if;
  end if;

  return query select
    (case when p_terapkan then 'DITERAPKAN' else 'UJI COBA' end)::text,
    (case when p_terapkan
          then format('%s digabung ke %s (aktif). batch #%s — bisa dibatalkan dengan batalkan_ubah_sales(%s)',
                      p_dari, p_ke, v_batch, v_batch)
          else format('Belum ada yang diubah. Jalankan gabungkan_sales(%L, %L, true) untuk menerapkan. '
                      'Sesudah diterapkan, %s dinonaktifkan dan %s diaktifkan.',
                      p_dari, p_ke, p_dari, p_ke) end)::text,
    v_total;
end $function$;
