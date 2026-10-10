CREATE OR REPLACE FUNCTION public.jaga_pelanggan_sp_sales()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_po_id bigint;
  v_po_cust bigint;
  v_po_rep bigint;
  v_po_no text;
  v_po_batal boolean;
  v_lain text;
  v_tautkan boolean := coalesce(current_setting('rhj.tautkan_po', true), '') = '1';
  v_nama text;
  v_lama text;
begin
  -- sistem/migrasi (tanpa sesi), owner/GM, Vonny (Vonny tidak punya PATCH langsung — RLS so_ubah; jalurnya hanya
  -- lengkapi_pelanggan_sp yang mencocokkan nama/No. HP dan menolak pelanggan sales lain)
  if auth.uid() is null or public.boleh_konfirmasi_kirim() then return new; end if;

  if tg_op = 'INSERT' then
    new.pelanggan_dari_po := false;   -- 135: penanda diisi sistem (tautkan_po_sp), bukan kiriman layar/REST
    if new.po_id is not null then
      select p.id, p.customer_id, p.sales_rep_id, p.no_po, p.batal into v_po_id, v_po_cust, v_po_rep, v_po_no, v_po_batal
        from public.purchase_orders p where p.id = new.po_id;
      -- (1) PO milik sales itu (jawaban sama dengan PO yang tidak ada)
      if v_po_id is null
         or (public.peran_saya() = 'sales'
             and not (public.pelanggan_saya(v_po_cust)
                      and (v_po_rep is null or v_po_rep = public.sales_rep_saya()))) then
        raise exception 'PO #% tidak ditemukan.', new.po_id using errcode = 'P0002';
      end if;
      -- (5) satu PO satu SP — sama dengan daftar po_belum_sp di layar dan tautkan_po_sp
      if v_po_batal then
        raise exception 'PO % sudah dibatalkan — tidak bisa dipakai Surat Pesanan baru.', v_po_no using errcode = '22023';
      end if;
      select s.no_sp into v_lain from public.sales_orders s
       where s.po_id = new.po_id and (not s.batal or s.batal_karena_barang) limit 1;
      if v_lain is not null then
        raise exception 'PO % sudah dipakai Surat Pesanan %. Satu PO hanya untuk satu SP.', v_po_no, v_lain
          using errcode = '23505';
      end if;
      if new.customer_id is null then
        new.customer_id := v_po_cust;   -- SP dari PO = pelanggan PO (layar memang mengirim pelanggan PO)
        return new;
      end if;
      if v_po_cust is null then
        raise exception
          'PO Surat Pesanan % belum tertaut ke data pelanggan, jadi SP-nya juga belum boleh menunjuk pelanggan — '
          'Vonny yang menautkan keduanya saat cek (nama & No. HP dicocokkan). Kosongkan pelanggannya, isi No. HP & '
          'alamat pelanggan, lalu simpan lagi.', coalesce(new.no_sp, '(baru)')
          using errcode = 'P0001';
      end if;
      return new;   -- pelanggan berbeda dari pelanggan PO ditolak jaga_po_menyusul
    end if;
    if new.customer_id is null then return new; end if;
  else
    -- 135: penanda "pelanggan dari PO menyusul" hanya diisi tautkan_po_sp
    if new.pelanggan_dari_po is distinct from old.pelanggan_dari_po and not v_tautkan then
      raise exception
        'Penanda "pelanggan dari PO menyusul" pada Surat Pesanan % diisi sistem saat PO ditempelkan dan tidak bisa '
        'diubah langsung.', coalesce(old.no_sp, '(baru)')
        using errcode = 'P0001';
    end if;
    -- (3) PO hanya ditempel lewat "Tempelkan PO"
    if new.po_id is distinct from old.po_id and not (v_tautkan and old.po_id is null) then
      raise exception
        'PO Surat Pesanan % hanya bisa ditempelkan lewat "Tempelkan PO" (SP yang belum ber-PO). Mengganti atau '
        'melepas PO-nya wewenang owner/GM.', coalesce(old.no_sp, '(baru)')
        using errcode = 'P0001';
    end if;
    -- (3) pelanggan hanya diisi otomatis dari PO yang ditempelkan
    if new.customer_id is distinct from old.customer_id then
      if v_tautkan and old.customer_id is null and new.po_id is not null then
        select p.customer_id into v_po_cust from public.purchase_orders p where p.id = new.po_id;
      end if;
      if v_po_cust is null or new.customer_id is distinct from v_po_cust then
        raise exception
          'Pelanggan Surat Pesanan % tidak bisa diganti langsung. SP yang belum tertaut ke data pelanggan ditautkan '
          'Vonny saat cek (nama & No. HP dicocokkan) atau otomatis saat PO pelanggannya ditempelkan; pelanggan yang '
          'sudah tertaut hanya bisa diganti owner/GM.', coalesce(old.no_sp, '(baru)')
          using errcode = 'P0001';
      end if;
    end if;
    if new.po_id is not null or new.customer_id is null
       or (new.kepada is not distinct from old.kepada and new.customer_id is not distinct from old.customer_id) then
      return new;
    end if;
  end if;

  -- (2) SP tanpa PO yang menunjuk pelanggan = dipilih dari daftar → Kepada = nama pelanggan itu
  select c.nama, c.nama_lama into v_nama, v_lama from public.customers c where c.id = new.customer_id;
  if v_nama is not null and public.pelanggan_saya(new.customer_id)   -- pelanggan sales lain: RLS yang menolak
     and public.kunci_nama_pelanggan(public.rhj_nama_rapi(new.kepada)) is distinct from public.kunci_nama_pelanggan(v_nama)
     and (v_lama is null
          or public.kunci_nama_pelanggan(public.rhj_nama_rapi(new.kepada)) is distinct from public.kunci_nama_pelanggan(v_lama)) then
    raise exception
      'Kepada pada Surat Pesanan % harus nama pelanggan yang dipilih dari daftar (%). Bila nama pelanggannya baru '
      'diubah, pilih ulang pelanggannya dari daftar; untuk nama lain, kosongkan pilihan pelanggannya lalu isi No. HP & '
      'alamat — Vonny menautkannya saat cek.',
      coalesce(new.no_sp, '(baru)'), v_nama
      using errcode = 'P0001';
  end if;
  return new;
end $function$;
