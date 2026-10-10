CREATE OR REPLACE FUNCTION public.simpan_pic_rekening(p_customer bigint, p_nama text, p_jabatan text, p_hp text, p_bank text, p_rek text, p_atas_nama text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.customer_pics; v_id bigint; v_rek text := nullif(btrim(p_rek), '');
begin
  -- gerbang-55: pemilik diperiksa sebelum apa pun dikerjakan
  if not public.pic_pelanggan_saya(p_customer) then raise exception 'Pelanggan ini bukan pelanggan Anda. PIC dan rekeningnya hanya bisa diisi sales yang memegang pelanggan itu — kalau tidak, EHC-nya bisa diarahkan ke rekening orang lain.' using errcode = '42501'; end if;
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak menyimpan PIC.';
  end if;
  if coalesce(btrim(p_nama), '') = '' then
    raise exception 'Nama PIC wajib diisi.';
  end if;
  if p_customer is null then
    raise exception 'PIC harus menempel pada satu perusahaan.';
  end if;
  -- Rekening tanpa bank (atau sebaliknya) menghasilkan baris yang tidak
  -- bisa ditransfer. Lebih baik ditolak sekarang daripada ketahuan saat
  -- uangnya mau dikirim.
  if (v_rek is not null) <> (coalesce(btrim(p_bank), '') <> '') then
    raise exception 'Bank dan nomor rekening harus diisi berdua, atau dikosongkan berdua.';
  end if;

  select * into v from public.customer_pics
   where customer_id = p_customer and lower(nama) = lower(btrim(p_nama));

  if not found then
    insert into public.customer_pics
      (customer_id, nama, jabatan, hp, bank, no_rekening, atas_nama)
    values (p_customer, btrim(p_nama), nullif(btrim(p_jabatan), ''), nullif(btrim(p_hp), ''),
            nullif(btrim(p_bank), ''), v_rek, nullif(btrim(p_atas_nama), ''))
    returning id into v_id;
    return v_id;
  end if;

  -- PIC-nya sudah ada. Rekening yang sudah terkunci tidak disentuh dari sini.
  if v.terkunci and v_rek is not null
     and (v_rek is distinct from v.no_rekening
       or nullif(btrim(p_bank), '') is distinct from v.bank) then
    raise exception 'Rekening % sudah terkunci (% %). Perubahannya harus lewat persetujuan GM, '
                    'bukan dari layar klaim.', v.nama, coalesce(v.bank, ''), coalesce(v.no_rekening, '');
  end if;

  update public.customer_pics
     set jabatan     = coalesce(nullif(btrim(p_jabatan), ''), jabatan),
         hp          = coalesce(nullif(btrim(p_hp), ''), hp),
         bank        = case when terkunci then bank      else nullif(btrim(p_bank), '') end,
         no_rekening = case when terkunci then no_rekening else v_rek end,
         atas_nama   = case when terkunci then atas_nama else nullif(btrim(p_atas_nama), '') end,
         aktif       = true
   where id = v.id;
  return v.id;
end $function$;
