CREATE OR REPLACE FUNCTION public.cek_kelayakan_vonny(p_so bigint DEFAULT NULL::bigint, p_hp text DEFAULT NULL::text, p_alamat text DEFAULT NULL::text)
 RETURNS TABLE(so_id bigint, siap boolean, kode text, pesan text, siapa text, tindakan text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s          public.sales_orders;
  v_status   text;
  v_kunci    text;
  v_hp_teks  text;
  v_hp       text;
  v_alamat   text;
  v_ada      public.customers;
  v_cocok    text;
  v_sales    text;
  v_sales_sp text;
  v_po_cust  bigint;
  v_po_nama  text;
  v_po_no    text;
  v_lampiran text;
  v_sales_po text;
  v_hitam        bigint;   -- 139
  v_hitam_nama   text;
  v_hitam_alasan text;
  v_hitam_cara   text;   -- 139s
  v_milik    public.customers;   -- 139r
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh memeriksa kelayakan SP.' using errcode = '42501';
  end if;

  for s in
    select x.* from public.sales_orders x
     where not x.batal
       and (case when p_so is null then x.status = 'menunggu vonny' else x.id = p_so end)
     order by x.id
  loop
    so_id := s.id; siap := false; kode := null; pesan := null; siapa := null; tindakan := null;
    select nama into v_sales_sp from public.sales_reps where id = s.sales_rep_id;

    -- 1 · syarat putuskan_vonny_cek
    v_status := public.status_sp_hitung(s.id);
    if v_status = 'menunggu gm' then
      kode := 'gm'; siapa := 'GM';
      pesan := 'Masih menunggu keputusan harga GM.';
      tindakan := 'GM memutuskan dulu di tab Menunggu Konfirmasi GM; sesudah itu SP ini bisa diloloskan.';
      return next; continue;
    end if;
    if v_status = 'draft' then
      kode := 'draft'; siapa := 'sales';
      pesan := 'SP belum punya baris barang.';
      tindakan := 'Sales melengkapi baris SP.';
      return next; continue;
    end if;
    if s.no_surat_jalan is not null or exists (select 1 from public.so_kirim k where k.so_id = s.id) then
      kode := 'terkirim'; siapa := 'owner/GM';
      pesan := 'Barang SP ini sudah mulai dikirim — keputusan cek Vonny tidak bisa diubah lagi.';
      tindakan := 'Hubungi owner/GM.';
      return next; continue;
    end if;

    -- 139 · pelanggan daftar hitam (keputusan Hannes 9 Okt no. 14): ditahan total — semua peran
    -- 139s (review 139 no. 3/6): No. HP tersimpan DAN No. HP yang diketik di laci sama-sama diperiksa
    v_hitam := null; v_hitam_cara := null;
    select r.id, r.cara into v_hitam, v_hitam_cara from public.sp_pelanggan_hitam_rinci(s.customer_id, s.po_id, s.kepada, s.telp) r limit 1;
    if v_hitam is null and nullif(btrim(coalesce(p_hp, '')), '') is not null then
      select r.id, r.cara into v_hitam, v_hitam_cara
        from public.sp_pelanggan_hitam_rinci(s.customer_id, s.po_id, s.kepada, btrim(p_hp)) r limit 1;
    end if;
    if v_hitam is not null then
      select c.nama, c.alasan_blacklist into v_hitam_nama, v_hitam_alasan from public.customers c where c.id = v_hitam;
      kode := 'blacklist'; siapa := 'owner/GM';
      pesan := case v_hitam_cara
                 when 'pelanggan' then 'Pelanggan "' || v_hitam_nama || '" masuk daftar hitam ('
                 when 'kembar' then 'Pelanggan SP ini cocok nama/No. HP dengan pelanggan daftar hitam "' || v_hitam_nama || '" ('
                 else 'Nama/No. HP SP ini cocok dengan pelanggan daftar hitam "' || v_hitam_nama || '" (' end
            || coalesce(v_hitam_alasan, 'tanpa keterangan') || ') — SP ini ditahan total.';
      tindakan := 'Owner/GM memutuskan: cabut daftar hitam pelanggan di tab Pelanggan, atau batalkan SP ini'
               || case v_hitam_cara
                    when 'pelanggan' then '.'
                    when 'kembar' then '; bila ini perusahaan/orang lain, beri pembeda pada nama (mis. kota/cabang) atau '
                                       || 'perbaiki No. HP pelanggannya di tab Pelanggan.'
                    else '; bila ini perusahaan/orang lain, ubah Kepada/No. HP lewat Minta ubah SP (beri pembeda, mis. '
                         || 'kota/cabang — disetujui GM), lalu tautkan.' end;
      return next; continue;
    end if;

    -- 135 · pelanggan diisi dari PO yang ditempel menyusul ("Tempelkan PO") → PO wajib berlampiran
    --       (keputusan Hannes 8 Okt, temuan #8: PO buatan sendiri untuk pelanggan berharga khusus)
    if s.pelanggan_dari_po and s.po_id is not null then
      select p.no_po, p.lampiran, sr.nama into v_po_no, v_lampiran, v_sales_po
        from public.purchase_orders p left join public.sales_reps sr on sr.id = p.sales_rep_id
       where p.id = s.po_id;
      if coalesce(btrim(v_lampiran), '') = '' then
        kode := 'lampiran_po';
        siapa := case when v_sales_po is not null then 'sales' else 'owner/GM/staff' end;
        pesan := 'Pelanggan SP ini diisi dari PO ' || coalesce(v_po_no, '#' || s.po_id)
              || ' yang ditempel menyusul, tetapi PO itu belum berlampiran.';
        tindakan := case when v_sales_po is not null then 'Sales ' || v_sales_po || ' (pemegang PO) atau owner/GM/staff'
                         else 'Owner/GM/staff' end
                 || ' mengunggah berkas PO customer di tab Upload PO (daftar PO › + unggah); sesudah itu Vonny '
                 || 'memeriksa lampirannya lalu meloloskan.';
        return next; continue;
      end if;
    end if;

    -- 2 · sudah tertaut ke data pelanggan → tinggal kategori (dipilih di laci)
    if s.customer_id is not null then
      siap := true; kode := 'ok';
      pesan := 'Sudah tertaut ke data pelanggan.';
      return next; continue;
    end if;

    -- 3 · belum tertaut: cocokkan seperti lengkapi_pelanggan_sp — nama, lalu No. HP
    v_ada := null; v_cocok := null; v_hp := null; v_po_cust := null; v_po_nama := null;
    if s.po_id is not null then   -- berkas 121: pelanggan PO yang ditempel (trigger tertunda so_pelanggan_po)
      select p.customer_id, c.nama into v_po_cust, v_po_nama
        from public.purchase_orders p left join public.customers c on c.id = p.customer_id
       where p.id = s.po_id;
    end if;
    v_hp_teks := coalesce(nullif(btrim(coalesce(p_hp, '')), ''), s.telp);
    v_kunci := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));   -- 139r: = nama yang disimpan
    -- 138 (keputusan Hannes 9 Okt no. 10): nama kembar — kembaran milik sales LAIN didahulukan (→ ditahan
    -- nama_sales_lain), lalu milik sales SP, lalu yang belum bertuan; dulu id terkecil (bisa kembaran belum bertuan).
    select c.* into v_ada from public.customers c
     where public.kunci_nama_pelanggan(c.nama) = v_kunci
        or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci)
     order by case when c.sales_rep_id is not null and c.sales_rep_id is distinct from s.sales_rep_id then 0
                   when c.sales_rep_id is not null then 1 else 2 end, c.id
     limit 1;
    if v_ada.id is not null then
      v_cocok := 'nama';
    else
      v_hp := public.hp_baku(v_hp_teks);
      if v_hp is not null then
        select c.* into v_ada from public.customers c where c.hp = v_hp order by c.id limit 1;
        if v_ada.id is not null then v_cocok := 'hp'; end if;
      end if;
    end if;

    if v_ada.id is not null then
      if v_ada.sales_rep_id is not null and s.sales_rep_id is not null and v_ada.sales_rep_id <> s.sales_rep_id then
        select nama into v_sales from public.sales_reps where id = v_ada.sales_rep_id;
        siapa := 'owner/GM';
        if v_cocok = 'hp' then
          kode := 'hp_sales_lain';
          pesan := 'No. HP ' || v_hp_teks || ' sudah dipakai pelanggan "' || v_ada.nama || '" yang dipegang sales '
                || coalesce(v_sales, 'lain') || ', bukan sales SP ini (' || coalesce(v_sales_sp, '—') || ').';
          tindakan := 'Periksa nomornya dulu — bila salah ketik atau bukan nomor pelanggan ini, perbaiki No. HP di laci cek (atau Minta ubah SP). Bila memang pelanggan '
                   || 'yang sama, owner/GM memindahkan pelanggannya ke ' || coalesce(v_sales_sp, 'sales SP')
                   || ' (tab Pelanggan).';   -- 139w: tanpa "Tautkan ke pelanggan tertentu" (No. HP unik, kandidat kosong)
        else
          kode := 'nama_sales_lain';
          -- 139r (review 138 no. 6/10): sales SP juga punya pelanggan bernama sama (atau ada yang belum bertuan) →
          -- sebut keduanya; owner/GM menautkan SP ke pelanggan yang benar (tautkan_pelanggan_sp)
          v_milik := null;
          select c.* into v_milik from public.customers c
           where c.id <> v_ada.id and not c.blacklist
             and (c.sales_rep_id is null or c.sales_rep_id = s.sales_rep_id)
             and (public.kunci_nama_pelanggan(c.nama) = v_kunci
                  or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci))
           order by case when c.sales_rep_id is not null then 0 else 1 end, c.id
           limit 1;
          if v_milik.id is not null then
            pesan := 'Nama "' || coalesce(s.kepada, '') || '" cocok dengan dua data pelanggan: "' || v_ada.nama
                  || '" (dipegang sales ' || coalesce(v_sales, 'lain') || ') dan "' || v_milik.nama || '" ('
                  || case when v_milik.sales_rep_id is null then 'belum bertuan'
                          else 'milik sales SP ini, ' || coalesce(v_sales_sp, '—') end || ').';
            tindakan := 'Owner/GM menautkan SP ini ke pelanggan yang benar (Tautkan ke pelanggan tertentu — laci cek atau '
                     || 'detail SP). Bila SP ini memang untuk "' || v_ada.nama || '", pindahkan pelanggannya ke '
                     || coalesce(v_sales_sp, 'sales SP') || ' di tab Pelanggan. Sesudah itu Vonny bisa meloloskan.';
          else
            pesan := 'Nama "' || coalesce(s.kepada, '') || '" cocok dengan pelanggan "' || v_ada.nama || '" yang dipegang sales '
                  || coalesce(v_sales, 'lain') || ', bukan sales SP ini (' || coalesce(v_sales_sp, '—') || ').';
            tindakan := 'Owner/GM memutuskan: bila memang pelanggan yang sama, pindahkan pelanggannya ke '
                     || coalesce(v_sales_sp, 'sales SP') || ' di tab Pelanggan; bila perusahaan/orang lain, ubah Kepada '
                     || 'lewat Minta ubah SP (beri pembeda, mis. kota/cabang). Sesudah itu Vonny bisa meloloskan.';
          end if;
        end if;
        return next; continue;
      end if;
      -- 139x (review 139s no. 6): cermin lengkapi_pelanggan_sp — pelanggan yang cocok (atau kembarannya) tertahan
      -- daftar hitam → tidak ditautkan; owner/GM yang memutuskan
      if public.sp_pelanggan_hitam(v_ada.id, null, null, null) is not null then
        kode := 'blacklist'; siapa := 'owner/GM';
        if v_ada.blacklist then
          pesan := 'Pelanggan "' || v_ada.nama || '" yang cocok dengan SP ini masuk daftar hitam ('
                || coalesce(v_ada.alasan_blacklist, 'tanpa keterangan') || ') — SP tidak bisa ditautkan ke sana.';
          tindakan := 'Owner/GM memutuskan: cabut daftar hitamnya di tab Pelanggan, atau batalkan SP; bila ini '
                   || 'perusahaan/orang lain, ubah Kepada/No. HP SP lewat Minta ubah SP (beri pembeda).';
        else
          pesan := 'SP ini cocok dengan pelanggan "' || v_ada.nama || '", yang cocok nama/No. HP dengan pelanggan daftar '
                || 'hitam "' || coalesce((select h.nama from public.customers h
                                          where h.id = public.sp_pelanggan_hitam(v_ada.id, null, null, null)), '—')
                || '" — SP tidak bisa ditautkan ke sana selama itu.';
          tindakan := 'Owner/GM memutuskan: bila "' || v_ada.nama || '" memang perusahaan/orang lain, beri pembeda pada '
                   || 'nama/No. HP-nya di tab Pelanggan; atau cabut daftar hitamnya; atau batalkan SP.';
        end if;
        return next; continue;
      end if;
      -- berkas 121 · cermin trigger so_y_hanya_gm (berkas 119): SP tanpa sales yang tertaut ke pelanggan Office
      if not public.setara_owner()
         and public.sp_khusus_gm(s.sales_rep_id, v_ada.id) and not public.sp_khusus_gm(s.sales_rep_id, null) then
        kode := 'office'; siapa := 'GM';
        pesan := 'Nama/No. HP SP ini cocok dengan pelanggan kantor "' || v_ada.nama
              || '" — SP pelanggan Office hanya dibuat/ditautkan GM atau owner.';
        tindakan := 'GM/owner yang meloloskan SP ini; bila memang bukan pelanggan kantor, periksa nama/No. HP SP.';
        return next; continue;
      end if;
      -- berkas 121 · cermin trigger po_jaga_blacklist: lengkapi_pelanggan_sp mengisi pelanggan PO yang masih kosong
      if v_ada.blacklist and s.po_id is not null and v_po_cust is null then
        kode := 'blacklist'; siapa := 'owner/GM';
        pesan := 'Pelanggan "' || v_ada.nama || '" masuk daftar hitam (' || coalesce(v_ada.alasan_blacklist, 'tanpa keterangan')
              || ') — SP ini tidak bisa ditautkan ke PO-nya.';
        tindakan := 'Owner/GM memutuskan: cabut daftar hitam pelanggan di tab Pelanggan, atau batalkan SP ini.';
        return next; continue;
      end if;
      -- berkas 121 · cermin trigger tertunda so_pelanggan_po: pelanggan SP harus sama dengan pelanggan PO
      if v_po_cust is not null and v_po_cust <> v_ada.id then
        kode := 'po_beda'; siapa := 'owner/GM';
        pesan := 'PO yang ditempel sudah atas nama pelanggan "' || coalesce(v_po_nama, '#' || v_po_cust)
              || '", sedangkan SP ini cocok dengan "' || v_ada.nama || '" — pelanggan SP dan PO harus sama.';
        tindakan := 'Owner/GM menyamakan: perbaiki nama "Kepada" SP lewat Minta ubah SP, atau perbaiki pelanggan PO.';
        return next; continue;
      end if;
      siap := true; kode := 'tautkan';
      pesan := 'Akan ditautkan ke pelanggan "' || v_ada.nama || '"'
            || case when v_cocok = 'hp' then ' (No. HP sama).' else '.' end;
      return next; continue;
    end if;

    -- 4 · pelanggan baru: syarat buat_pelanggan_baru
    if coalesce(btrim(v_hp_teks), '') = '' or v_hp is null then
      kode := 'hp_kosong'; siapa := 'Vonny';
      pesan := 'No. HP pelanggan belum ada — pelanggan baru wajib punya No. HP.';
      tindakan := 'Isi No. HP pelanggan di laci cek (tanyakan ke sales ' || coalesce(v_sales_sp, '') || ' bila belum tahu).';
      return next; continue;
    end if;
    if v_hp !~ '^[1-9][0-9]{8,15}$' then
      kode := 'hp_salah'; siapa := 'Vonny';
      pesan := 'No. HP "' || v_hp_teks || '" tidak valid — harus 9 sampai 16 angka.';
      tindakan := 'Perbaiki No. HP di laci cek.';
      return next; continue;
    end if;
    v_alamat := coalesce(nullif(btrim(coalesce(p_alamat, '')), ''), btrim(coalesce(s.alamat, '')));
    if v_alamat = '' then
      kode := 'alamat_kosong'; siapa := 'Vonny';
      pesan := 'Alamat pelanggan belum ada — pelanggan baru wajib punya alamat.';
      tindakan := 'Isi alamat pelanggan di laci cek.';
      return next; continue;
    end if;
    if char_length(v_kunci) < 2 then
      kode := 'nama_pendek'; siapa := 'sales';
      pesan := 'Nama "' || coalesce(s.kepada, '') || '" terlalu pendek untuk dijadikan pelanggan.';
      tindakan := 'Sales/owner memperbaiki nama "Kepada" di SP.';
      return next; continue;
    end if;
    -- 139y (review 139w no. 4): pelanggan baru bernama non-Latin hanya dibuat owner/GM/staff (customers_tolak_nama_ganda)
    if coalesce(public.peran_saya(), '') not in ('owner','gm','staff')
       and public.ada_huruf_non_latin(public.rhj_nama_rapi(s.kepada)) then
      kode := 'nama_non_latin'; siapa := 'owner/GM';
      pesan := 'Nama "' || coalesce(s.kepada, '') || '" memuat huruf atau simbol di luar huruf Latin biasa — pelanggan '
            || 'barunya hanya bisa dibuat owner/GM/staff.';
      tindakan := 'Owner/GM menautkan/melengkapi pelanggan SP ini sendiri (laci cek atau detail SP), atau Kepada diubah '
               || 'ke huruf biasa lewat Minta ubah SP.';
      return next; continue;
    end if;
    if s.sales_rep_id is null then
      kode := 'sales_kosong'; siapa := 'owner/GM';
      pesan := 'SP belum punya sales — pelanggan baru butuh sales PIC.';
      tindakan := 'Owner/GM/staff mengisi sales SP.';
      return next; continue;
    end if;
    if not exists (select 1 from public.sales_reps where id = s.sales_rep_id and aktif) then
      kode := 'sales_nonaktif'; siapa := 'owner/GM';
      pesan := 'Sales SP (' || coalesce(v_sales_sp, '—') || ') sudah nonaktif — tidak bisa jadi sales PIC pelanggan baru.';
      tindakan := 'Owner/GM/staff mengganti sales SP.';
      return next; continue;
    end if;
    if v_po_cust is not null then   -- berkas 121: pelanggan baru pasti beda dengan pelanggan PO
      kode := 'po_beda'; siapa := 'owner/GM';
      pesan := 'PO yang ditempel sudah atas nama pelanggan "' || coalesce(v_po_nama, '#' || v_po_cust)
            || '", sedangkan "' || coalesce(s.kepada, '') || '" belum ada di data pelanggan — pelanggan SP dan PO harus sama.';
      tindakan := 'Owner/GM menyamakan: perbaiki nama "Kepada" SP lewat Minta ubah SP sesuai pelanggan PO.';
      return next; continue;
    end if;
    siap := true; kode := 'baru';
    pesan := 'Pelanggan baru "' || coalesce(s.kepada, '') || '" akan dibuat (HP ' || v_hp || ', sales PIC '
          || coalesce(v_sales_sp, '—') || ').';
    return next;
  end loop;
end $function$;
