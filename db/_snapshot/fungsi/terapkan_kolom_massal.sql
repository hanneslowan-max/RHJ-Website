CREATE OR REPLACE FUNCTION public.terapkan_kolom_massal(p_jenis text, p_cara text, p_nilai text, p_produk bigint[], p_catatan text DEFAULT NULL::text, p_tempel jsonb DEFAULT NULL::jsonb, p_paksa boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  kol  text := public.kolom_massal(p_jenis);
  tipe text;
  n_timpa int; n_taksah int; n_ubah int; b_id bigint;
begin
  if kol is null then
    raise exception 'Jenis "%" bukan kolom produk.', p_jenis using errcode = '22023';
  end if;
  if not public.boleh_massal(p_jenis) then
    raise exception 'Anda tidak berwenang mengubah kolom % secara massal.', p_jenis
      using errcode = '42501';
  end if;
  if coalesce(array_length(p_produk, 1), 0) = 0 then
    raise exception 'Tidak ada produk yang dipilih.' using errcode = '22023';
  end if;

  select count(*) filter (where tanda = 'timpa'),
         count(*) filter (where tanda = 'tak_sah'),
         count(*) filter (where tanda in ('isi','timpa'))
    into n_timpa, n_taksah, n_ubah
    from public.hitung_kolom_massal(p_jenis, p_cara, p_nilai, p_produk, p_tempel);

  -- Nilai di luar daftar tidak pernah boleh lewat, dipaksa pun tidak.
  if n_taksah > 0 then
    raise exception 'Ditolak: % baris berisi nilai yang tidak sah untuk %. Perbaiki dulu nilainya.',
      n_taksah, p_jenis using errcode = '23514';
  end if;

  -- Mengisi kolom yang masih kosong itu pekerjaan sehari-hari. Menimpa
  -- nilai yang sudah ada dengan yang berbeda itu yang perlu dilihat dua
  -- kali — biasanya tandanya saringannya kelewat lebar.
  if n_timpa > 0 and not p_paksa then
    raise exception 'Ditahan: % produk sudah punya nilai lain dan akan tertimpa. Periksa saringannya, atau centang "tetap terapkan".',
      n_timpa using errcode = '23514';
  end if;

  if n_ubah = 0 then
    raise exception 'Tidak ada yang berubah — semua produk terpilih sudah bernilai segitu.'
      using errcode = '22023';
  end if;

  insert into public.edit_massal (jenis, cara, nilai, nilai_teks, pembulatan, berlaku_dari,
                                  jumlah_baris, catatan, dipaksa, dibuat_oleh)
  values (p_jenis, p_cara, null, p_nilai, 0, current_date,
          n_ubah, p_catatan, p_paksa, auth.uid())
  returning id into b_id;

  insert into public.edit_massal_nilai (batch_id, product_id, lama, baru)
  select b_id, product_id, lama, baru
    from public.hitung_kolom_massal(p_jenis, p_cara, p_nilai, p_produk, p_tempel)
   where tanda in ('isi','timpa');

  /* tipe kolomnya dibaca dari katalog, bukan ditebak: kelompok/fungsi/bahan
     itu text, diameter_mm itu numeric — dan yang tersimpan di
     edit_massal_nilai selalu teks, jadi harus dikembalikan ke tipe aslinya */
  select format_type(a.atttypid, a.atttypmod) into tipe
    from pg_attribute a
   where a.attrelid = 'public.products'::regclass and a.attname = kol;

  execute format(
    'update public.products p set %1$I = n.baru::%2$s
       from public.edit_massal_nilai n
      where n.batch_id = $1 and n.product_id = p.id', kol, tipe)
    using b_id;

  return b_id;
end $function$;
