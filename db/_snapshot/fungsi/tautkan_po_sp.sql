CREATE OR REPLACE FUNCTION public.tautkan_po_sp(p_so bigint, p_po bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_so record; v_po record; v_sp numeric; v_nilai numeric; v_lain text; v_tahan boolean;
begin
  if not public.boleh_input_po() then
    raise exception 'Anda tidak berwenang menempelkan PO ke Surat Pesanan.'
      using errcode = '42501';
  end if;

  select * into v_so from public.sales_orders where id = p_so;
  if v_so.id is null then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002';
  end if;
  -- 134 · pemilik SP, dipasang SEBELUM satu pun pesan yang menyebut isi SP. Jawabannya sengaja sama dengan
  -- "SP tidak ada" (dulu sales bisa menempelkan PO-nya ke SP sales lain, dan pesan selisih total membocorkan
  -- nomor & grand total SP itu).
  if public.peran_saya() = 'sales' and v_so.sales_rep_id is distinct from public.sales_rep_saya() then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002';
  end if;
  if v_so.batal then
    raise exception 'Surat Pesanan % sudah dibatalkan.', v_so.no_sp using errcode = '22023';
  end if;
  if v_so.po_id is not null then
    raise exception 'Surat Pesanan % sudah menunjuk sebuah PO. Kalau PO-nya keliru, '
                    'perbaiki lewat "Minta ubah SP" supaya perpindahannya tercatat.',
                    v_so.no_sp using errcode = '22023';
  end if;

  select * into v_po from public.purchase_orders where id = p_po;
  if v_po.id is null then
    raise exception 'PO #% tidak ditemukan.', p_po using errcode = 'P0002';
  end if;
  -- gerbang-58 · pemilik PO, dipasang SEBELUM satu pun pesan yang
  -- menyebut isi PO. Jawabannya sengaja SAMA dengan "PO tidak ada":
  -- membedakan keduanya tetap memberi tahu bahwa PO itu ada.
  if public.peran_saya() = 'sales'
     and not (public.pelanggan_saya(v_po.customer_id)
              and (v_po.sales_rep_id is null
                   or v_po.sales_rep_id = public.sales_rep_saya())) then
    raise exception 'PO #% tidak ditemukan.', p_po using errcode = 'P0002';
  end if;
  if v_po.batal then
    raise exception 'PO % sudah dibatalkan — tidak bisa ditempelkan ke Surat Pesanan.',
                    v_po.no_po using errcode = '22023';
  end if;

  -- Satu PO satu SP. Kalau sudah dipakai, sebutkan SP mananya: tanpa itu
  -- orang akan mengira PO-nya salah ketik dan mengetik ulang PO kedua
  -- dengan nomor yang sama.
  select s.no_sp into v_lain
    from public.sales_orders s
   where s.po_id = p_po and not s.batal and s.id <> p_so
   limit 1;
  if v_lain is not null then
    raise exception 'PO % sudah dipakai Surat Pesanan %. Satu PO hanya untuk satu SP.',
                    v_po.no_po, v_lain using errcode = '23505';
  end if;

  -- Pelanggannya harus sama. Ini penjagaan yang paling sering terpakai:
  -- PO menyusul dicari dengan mata, dan nomor PO dua pelanggan bisa mirip.
  if v_so.customer_id is not null and v_po.customer_id is not null
     and v_so.customer_id <> v_po.customer_id then
    raise exception 'PO % milik "%", sedangkan Surat Pesanan % untuk "%". '
                    'Periksa lagi — PO ini bukan milik pesanan itu.',
                    v_po.no_po, v_po.nama_customer, v_so.no_sp, v_so.kepada
      using errcode = '23514';
  end if;

  -- #30 (berkas 114): SP mengikuti mode PPN PO — beda mode ditolak dengan pesan yang menyebutnya.
  if v_so.mode_ppn is distinct from v_po.mode_ppn then
    raise exception 'Surat Pesanan % memakai %, sedangkan PO % memakai %. SP mengikuti PO — '
                    'ubah dulu mode PPN SP-nya (Minta ubah SP), lalu tempelkan PO-nya.',
                    v_so.no_sp, public.label_mode_ppn(v_so.mode_ppn), v_po.no_po, public.label_mode_ppn(v_po.mode_ppn)
      using errcode = '23514';
  end if;

  -- Angkanya diperiksa DI SINI, bukan dibiarkan meledak dari trigger,
  -- supaya selisihnya bisa disebut. Triggernya tetap berjalan sesudah
  -- update di bawah — penjagaan gandanya sengaja.
  select coalesce(r.grand_total, 0) into v_sp
    from public.so_ringkas r where r.so_id = p_so;
  select coalesce(p.grand_total, 0) into v_nilai
    from public.po_ringkas p where p.po_id = p_po;
  if round(coalesce(v_sp,0), 2) <> round(coalesce(v_nilai,0), 2) then   -- #12: sama sampai sen
    raise exception 'Grand total Surat Pesanan % (%) tidak sama dengan PO % (%) — '
                    'selisih %. Betulkan salah satunya dulu; menempelkan PO yang '
                    'angkanya beda akan membuat invoice ditolak pelanggan.',
                    v_so.no_sp, public.rp_teks(v_sp),
                    v_po.no_po,  public.rp_teks(v_nilai),
                    public.rp_teks(abs(coalesce(v_sp,0) - coalesce(v_nilai,0)))
      using errcode = '23514';
  end if;

  -- po_menyusul dipadamkan oleh jaga_po_menyusul(), tidak perlu di sini.
  -- 134: bendera transaksi — jaga_pelanggan_sp_sales hanya mengizinkan po_id/customer_id berubah lewat sini.
  perform set_config('rhj.tautkan_po', '1', true);
  update public.sales_orders
     set po_id = p_po,
         -- isi-pelanggan-58
         customer_id = coalesce(customer_id, v_po.customer_id),
         -- 135: pelanggan SP diisi dari PO yang ditempel menyusul → cek Vonny menahan sampai PO berlampiran
         pelanggan_dari_po = pelanggan_dari_po or (customer_id is null and v_po.customer_id is not null),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_so;
  perform set_config('rhj.tautkan_po', '', true);

  -- 135b: pelanggan baru diisi dari PO ini & PO tanpa lampiran → cek Vonny yang sudah lolos digugurkan untuk SEMUA
  -- peran (trigger so_vonny_gugur melewati Vonny/GM/owner), dan pemanggil diberi tahu SP menunggu lampiran.
  v_tahan := v_so.customer_id is null and v_po.customer_id is not null and not coalesce(v_so.pelanggan_dari_po, false)
             and coalesce(btrim(v_po.lampiran), '') = '';
  if v_tahan then
    perform public.gugurkan_cek_vonny(p_so);
    return 'PO ' || v_po.no_po || ' menempel ke Surat Pesanan ' || v_so.no_sp || '. Pelanggannya diisi dari PO ini, '
           || 'jadi SP baru bisa diloloskan cek Vonny setelah PO ' || v_po.no_po || ' berlampiran — unggah berkas PO '
           || 'customer di tab Upload PO (daftar PO › + unggah).';
  end if;
  return 'PO ' || v_po.no_po || ' menempel ke Surat Pesanan ' || v_so.no_sp
         || '. Invoice sudah boleh diterbitkan.';
end $function$;
