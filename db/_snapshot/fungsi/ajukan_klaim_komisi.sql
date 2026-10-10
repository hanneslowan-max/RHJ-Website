CREATE OR REPLACE FUNCTION public.ajukan_klaim_komisi(p_so bigint, p_tanggal date, p_berkas jsonb DEFAULT '[]'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_rep bigint; v_rek public.sales_rep_rekening;
        v_nominal numeric; b jsonb;
begin
  -- gerbang-55: pemilik diperiksa sebelum apa pun dikerjakan
  if not public.boleh_lihat_sp(p_so) then raise exception 'Surat Pesanan ini bukan milik Anda. Klaim komisi hanya bisa diajukan atas SP yang Anda pegang sendiri.' using errcode = '42501'; end if;
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengajukan klaim komisi.';
  end if;
  if p_berkas is not null and jsonb_typeof(p_berkas) <> 'array' then
    raise exception 'Daftar lampiran tidak berbentuk daftar.';
  end if;
  for b in select * from jsonb_array_elements(coalesce(p_berkas, '[]'::jsonb)) loop
    if coalesce(btrim(b->>'nama_berkas'), '') = '' or coalesce(btrim(b->>'path'), '') = '' then
      raise exception 'Ada lampiran yang tidak punya nama berkas atau alamat penyimpanan.';
    end if;
  end loop;

  select sales_rep_id into v_rep from public.sales_orders where id = p_so;
  if not found then raise exception 'Surat Pesanan tidak ditemukan.'; end if;
  -- Diperiksa di sini juga, bukan cuma diserahkan ke indeks unik: pesan
  -- "duplicate key value violates unique constraint" tidak menolong siapa
  -- pun yang sedang memakai layar.
  if exists (select 1 from public.komisi_klaim where so_id = p_so) then
    raise exception 'Komisi SP ini sudah pernah diklaim. Satu SP satu klaim komisi.';
  end if;
  if v_rep is null then
    raise exception 'SP ini belum punya sales. Komisinya tidak tahu harus ke siapa.';
  end if;

  select * into v_rek from public.sales_rep_rekening where sales_rep_id = v_rep;
  if not found then
    raise exception 'Rekening sales belum diisi. Minta finance mengisinya lebih dulu — '
                    'sales tidak bisa mengisinya sendiri.';
  end if;

  -- Nominalnya DIHITUNG, tidak diterima. Ini inti berkas ini.
  v_nominal := public.komisi_hitung(p_so);
  if v_nominal is null then
    raise exception 'Komisi SP ini belum ada angkanya — GM belum menetapkan '
                    'persentase untuk invoice yang telat.';
  end if;

  perform set_config('rhj.klaim_komisi', 'on', true);

  insert into public.komisi_klaim (so_id, bank, no_rekening, atas_nama, tanggal)
  values (p_so, v_rek.bank, v_rek.no_rekening, v_rek.atas_nama,
          coalesce(p_tanggal, current_date))
  returning id into v_id;

  insert into public.komisi_klaim_nilai (klaim_id, nominal) values (v_id, v_nominal);

  insert into public.komisi_klaim_berkas (klaim_id, nama_berkas, path, ukuran, mime, dibuat_oleh)
  select v_id, btrim(x->>'nama_berkas'), btrim(x->>'path'),
         nullif(x->>'ukuran', '')::bigint, nullif(btrim(x->>'mime'), ''), auth.uid()
    from jsonb_array_elements(coalesce(p_berkas, '[]'::jsonb)) x;

  perform set_config('rhj.klaim_komisi', 'off', true);
  return v_id;
end $function$;
