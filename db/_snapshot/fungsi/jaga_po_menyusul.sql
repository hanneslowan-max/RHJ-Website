CREATE OR REPLACE FUNCTION public.jaga_po_menyusul()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- PO sudah menempel: penandanya tidak boleh tertinggal menyala. Kalau
  -- dibiarkan, antrean "menunggu PO" akan memuat SP yang PO-nya sudah
  -- datang — dan antrean yang memuat pekerjaan selesai akan diabaikan
  -- seluruhnya dalam dua minggu.
  if new.po_id is not null and new.po_menyusul then
    new.po_menyusul := false;
  end if;

  -- Stempel siapa & kapan, sekali saja saat penandanya dinyalakan.
  if new.po_menyusul and (tg_op = 'INSERT' or not coalesce(old.po_menyusul, false)) then
    new.po_menyusul_oleh := coalesce(new.po_menyusul_oleh, auth.uid());
    new.po_menyusul_pada := coalesce(new.po_menyusul_pada, now());
  end if;

  -- Pelanggan PO dan pelanggan SP harus orang yang sama. Diperiksa di
  -- trigger, bukan cuma di tautkan_po_sp(), karena po_id juga bisa diisi
  -- langsung saat SP dibuat — dan PO menyusul dicari dengan mata, dari
  -- tumpukan kertas, di mana nomor dua pelanggan bisa mirip.
  if new.po_id is not null
     and (tg_op = 'INSERT' or new.po_id is distinct from old.po_id)
     and new.customer_id is not null then
    if exists (select 1 from public.purchase_orders p
                where p.id = new.po_id
                  and p.customer_id is not null
                  and p.customer_id <> new.customer_id) then
      raise exception
        'PO yang ditunjuk Surat Pesanan % milik pelanggan lain. Periksa lagi '
        'nomor PO-nya — pesanan satu pelanggan tidak boleh ditagihkan atas PO '
        'pelanggan lain.', coalesce(new.no_sp, '(baru)')
        using errcode = '23514';
    end if;
  end if;

  -- Pengecualian "invoice tanpa PO" tidak boleh dinyalakan dengan PATCH
  -- biasa. Satu pintu: izinkan_invoice_tanpa_po(), yang memeriksa peran,
  -- mewajibkan alasan, dan mencatat siapa & kapan. set_config-nya berlaku
  -- hanya di dalam transaksi fungsi itu, jadi pintunya tidak bisa dibuka
  -- dari layar.
  if coalesce(current_setting('rhj.tanpa_po', true), '') <> '1'
     and ((tg_op = 'INSERT' and new.tanpa_po_ok)
       or (tg_op = 'UPDATE' and new.tanpa_po_ok is distinct from old.tanpa_po_ok)) then
    raise exception
      'Pengecualian "invoice tanpa PO" tidak bisa diisi langsung. Pakai tombolnya — '
      'hanya owner/GM, wajib beralasan, dan tercatat siapa yang memberi.'
      using errcode = '42501';
  end if;

  -- Melepas PO dari SP yang invoicenya sudah terbit akan membuat invoice
  -- itu menggantung tanpa pesanan — dan gerbang di bawah tidak akan
  -- menangkapnya, karena nomor invoicenya sendiri tidak berubah.
  if tg_op = 'UPDATE' and old.po_id is not null and new.po_id is null
     and new.no_invoice is not null and not new.batal then
    raise exception
      'PO tidak bisa dilepas dari Surat Pesanan % selama invoice % masih ada. '
      'Hapus invoicenya lebih dulu, atau perbaiki PO-nya — jangan dilepas.',
      new.no_sp, new.no_invoice
      using errcode = '23514';
  end if;

  return new;
end $function$;
