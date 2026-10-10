CREATE OR REPLACE FUNCTION public.jaga_pemilik_dokumen()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_saya bigint; v_nama text;
begin
  if public.peran_saya() <> 'sales' then
    return new;                      -- owner/GM/staff memilih sendiri
  end if;

  v_saya := public.sales_rep_saya();
  if v_saya is null then
    -- Pesan yang menyebut PEKERJAANNYA, bukan nama policy. Ini keadaan
    -- yang benar-benar terjadi dan dulu berbunyi "new row violates
    -- row-level security policy" — kalimat yang tidak menolong siapa pun.
    raise exception
      'Akun Anda belum ditautkan ke nama sales, jadi dokumen ini tidak punya '
      'pemilik dan Anda sendiri tidak akan bisa membukanya lagi. Minta owner '
      'membuka tab Pengguna lalu mengisi "Masuk sebagai" untuk akun ini.'
      using errcode = '42501';
  end if;

  if new.sales_rep_id is null then
    new.sales_rep_id := v_saya;      -- yang membuat, itu yang memegang
    return new;
  end if;

  if new.sales_rep_id <> v_saya then
    select nama into v_nama from public.sales_reps where id = new.sales_rep_id;
    raise exception
      'Dokumen ini akan tercatat atas nama % — bukan Anda. Sales hanya bisa '
      'membuat PO dan SP untuk dirinya sendiri; kalau pelanggan ini memang '
      'dipegang %, mintalah owner, GM, atau staff yang membuatkannya.',
      coalesce(v_nama, '#' || new.sales_rep_id), coalesce(v_nama, 'orang lain')
      using errcode = '42501';
  end if;
  return new;
end $function$;
