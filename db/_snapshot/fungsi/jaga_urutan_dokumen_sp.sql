CREATE OR REPLACE FUNCTION public.jaga_urutan_dokumen_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tahan boolean; v_perlu boolean;
begin
  if new.batal then return new; end if;

  -- Hanya saat nomornya BARU DIISI atau DIGANTI. Lihat berkas 39: kalau
  -- diperiksa di setiap update, SP yang terlanjur punya dokumen akan
  -- membeku total — statusnya tidak bisa dihitung ulang sekali pun.
  if ((tg_op = 'INSERT' and (new.no_surat_jalan is not null or new.no_invoice is not null))
      or (tg_op = 'UPDATE'
          and (new.no_surat_jalan is distinct from old.no_surat_jalan
               or new.no_invoice is distinct from old.no_invoice)
          and (new.no_surat_jalan is not null or new.no_invoice is not null)))
  then
    -- gerbang 1: harga di bawah price list, belum diputus GM (berkas 39)
    select coalesce(r.ada_bawah_list, false) and new.harga_ok is not true
      into v_tahan
      from public.so_ringkas r where r.so_id = new.id;
    if coalesce(v_tahan, false) then
      raise exception 'Surat Pesanan % masih menunggu keputusan GM karena ada harga di '
                      'bawah price list. Surat jalan dan invoice belum boleh diisi — '
                      'barangnya belum boleh keluar sebelum harganya diputuskan.', new.no_sp
        using errcode = '23514';
    end if;

    -- gerbang 0 (139, keputusan Hannes 9 Okt no. 14 & 16): pelanggan daftar hitam → SURAT JALAN ditahan total
    -- (izin kirim tidak membukanya). Invoice/faktur/pelunasan barang yang sudah keluar, dan penutupan surat jalan
    -- bertahap yang sudah terbit (rhj.sj_final, mis. sisa dibatalkan), tetap jalan.
    if new.no_surat_jalan is not null
       and (tg_op = 'INSERT' or old.no_surat_jalan is null)   -- 139s: koreksi nomor yang sudah terbit bukan kiriman baru
       and coalesce(current_setting('rhj.sj_final', true), '') <> '1' then
      perform public.tahan_daftar_hitam_sp(new.no_sp, new.customer_id, new.po_id, new.kepada, new.telp);
    end if;

    -- gerbang 2: pelanggan yang perlu dikonfirmasi sebelum kirim (berkas 41)
    select coalesce(c.perlu_konfirmasi, false) into v_perlu
      from public.customers c where c.id = new.customer_id;
    if coalesce(v_perlu, false) and new.kirim_ok is not true then
      raise exception 'Pelanggan Surat Pesanan % ditandai perlu konfirmasi sebelum '
                      'pengiriman. Vonny atau GM harus mengizinkan dulu di antrean '
                      'konfirmasi — barangnya belum boleh keluar.', new.no_sp
        using errcode = '23514';
    end if;

    -- gerbang 3a: barang keluar tanpa PO harus DINYATAKAN (berkas 42).
    -- Syaratnya tidak dipasang saat SP dibuat, melainkan di sini. SP yang
    -- baru diketik tanpa PO masih mungkin sekadar setengah jadi — dan
    -- menolaknya saat itu juga berarti menolak draf. Yang tidak boleh
    -- samar adalah BARANG YANG BERANGKAT: di detik itu keadaannya sudah
    -- sengaja, jadi alasannya harus ada namanya.
    if new.no_surat_jalan is not null and new.po_id is null
       and not new.po_menyusul and not new.tanpa_po_ok then
      raise exception
        'Surat jalan % dibuat untuk Surat Pesanan % yang belum punya PO. '
        'Barangnya boleh berangkat, tapi keadaan ini harus dinyatakan: tandai '
        '"PO menyusul" dan tulis alasannya. Tanpa itu SP ini tidak bisa '
        'dibedakan dari SP yang PO-nya lupa diisi — dan invoicenya akan '
        'tertahan tanpa ada yang tahu kenapa.',
        new.no_surat_jalan, new.no_sp
        using errcode = '23514';
    end if;

    -- gerbang 3b: invoice ditahan sampai PO menempel.
    -- Perhatikan yang TIDAK ditahan di sini: surat jalan. Barangnya boleh
    -- berangkat; yang belum boleh adalah menagihnya.
    if new.no_invoice is not null and new.po_id is null and not new.tanpa_po_ok then
      raise exception
        'Invoice % belum boleh terbit untuk Surat Pesanan %: PO pelanggannya belum '
        'menempel. Surat jalan boleh — barangnya memang sudah berangkat — tapi '
        'tagihan tanpa nomor PO akan ditolak bagian hutang pelanggan. Tempelkan '
        'PO-nya lewat "Tempelkan PO", atau minta owner/GM memberi pengecualian '
        'kalau pelanggan ini memang tidak pernah menerbitkan PO.',
        new.no_invoice, new.no_sp
        using errcode = '23514';
    end if;
  end if;

  -- ── nomor dan tanggal berpasangan ──
  if (new.no_surat_jalan is not null) <> (new.tgl_surat_jalan is not null) then
    raise exception 'Nomor surat jalan dan tanggalnya harus diisi bersama. '
                    'Surat jalan tanpa tanggal tidak bisa dipakai menghitung umur invoice.';
  end if;
  if (new.no_invoice is not null) <> (new.tgl_invoice is not null) then
    raise exception 'Nomor invoice dan tanggalnya harus diisi bersama. '
                    'Tanggal invoice yang menentukan batas 120 hari, jadi ia tidak boleh kosong.';
  end if;
  if (new.no_faktur is not null) <> (new.tgl_faktur is not null) then
    raise exception 'Nomor faktur dan tanggalnya harus diisi bersama.';
  end if;

  -- ── urutan maju ──
  if new.no_invoice is not null and new.no_surat_jalan is null then
    raise exception 'Invoice % tidak bisa diisi sebelum ada surat jalan. '
                    'Barangnya belum keluar, jadi belum ada yang ditagih.', new.no_invoice;
  end if;
  if new.no_faktur is not null and new.no_invoice is null then
    raise exception 'Faktur % tidak bisa diisi sebelum ada invoice. '
                    'Faktur pajak diterbitkan atas tagihan, jadi tagihannya harus ada '
                    'lebih dulu.', new.no_faktur;
  end if;
  if new.lunas and new.no_invoice is null then
    raise exception 'Surat Pesanan % tidak bisa ditandai lunas sebelum ada invoice. '
                    'Pelunasan adalah gerbang klaim EHC dan komisi, jadi ia harus punya '
                    'dokumen tagihan yang menjelaskan uang mana yang masuk.', new.no_sp;
  end if;
  if new.lunas and new.tgl_lunas is null then
    raise exception 'Tanggal pelunasan wajib diisi. Tanggal itu yang menentukan kapan '
                    'klaim EHC dan komisi terbuka.';
  end if;

  -- ── urutan mundur ──
  if tg_op = 'UPDATE' then
    if old.no_surat_jalan is not null and new.no_surat_jalan is null
       and new.no_invoice is not null then
      raise exception 'Surat jalan tidak bisa dihapus selama invoice % masih ada. '
                      'Hapus invoicenya lebih dulu.', new.no_invoice;
    end if;
    if old.no_invoice is not null and new.no_invoice is null and new.no_faktur is not null then
      raise exception 'Invoice tidak bisa dihapus selama faktur % masih ada. '
                      'Hapus fakturnya lebih dulu.', new.no_faktur;
    end if;
    if old.no_invoice is not null and new.no_invoice is null and new.lunas then
      raise exception 'Invoice tidak bisa dihapus selama Surat Pesanan masih ditandai lunas. '
                      'Batalkan pelunasannya lebih dulu.';
    end if;
  end if;

  return new;
end $function$;
