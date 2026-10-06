-- ═══════════════════════════════════════════════════════════════════════
-- 121 · #50 perbaikan hasil review: cek_kelayakan_vonny ikut mencerminkan penolakan lain + indeks nama
--
-- Review adversarial atas berkas 120 menemukan kasus di mana cek berkata "siap" tetapi meloloskan tetap
-- ditolak database (tombol terbuka, galat baru muncul sesudah ditekan — persis yang ingin dicegah #50):
--   · pelanggan DAFTAR HITAM yang PO-nya belum bertuan → trigger po_jaga_blacklist menolak saat
--     lengkapi_pelanggan_sp mengisi pelanggan PO;                                   → kode 'blacklist'
--   · PO yang ditempel sudah atas nama pelanggan LAIN → trigger tertunda so_pelanggan_po menolak saat
--     COMMIT (termasuk pelanggan baru, yang pasti beda);                            → kode 'po_beda'
--   · SP tanpa sales yang cocok dengan pelanggan OFFICE → trigger so_y_hanya_gm (berkas 119) menolak
--     peran selain GM/owner;                                                        → kode 'office'
-- Urutannya mengikuti urutan penolakan nyata: sales lain → Office → daftar hitam → PO beda.
--
-- Indeks ekspresi kunci_nama_pelanggan(nama) & (nama_lama): pencocokan nama tidak lagi memindai
-- seluruh pelanggan per SP (uji DEV, 9 SP antrean: ±740 ms → ±8 ms; perlu ANALYZE); lengkapi_pelanggan_sp & buat_pelanggan_baru
-- ikut cepat. kunci_nama_pelanggan IMMUTABLE — bila isinya diubah kelak, indeks ini wajib REINDEX.
--
-- Tidak ada data yang diubah.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.cek_kelayakan_vonny(p_so bigint default null, p_hp text default null,
                                                      p_alamat text default null)
returns table (so_id bigint, siap boolean, kode text, pesan text, siapa text, tindakan text)
language plpgsql stable security definer set search_path = public as $$
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
    v_kunci := public.kunci_nama_pelanggan(s.kepada);
    select c.* into v_ada from public.customers c
     where public.kunci_nama_pelanggan(c.nama) = v_kunci
        or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci)
     order by c.id limit 1;
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
          tindakan := 'Periksa nomornya dulu — bila salah ketik, perbaiki No. HP di laci cek. Bila memang pelanggan '
                   || 'yang sama, owner/GM memindahkan pelanggannya ke ' || coalesce(v_sales_sp, 'sales SP')
                   || ' (tab Pelanggan) atau mengganti sales SP.';
        else
          kode := 'nama_sales_lain';
          pesan := 'Nama "' || coalesce(s.kepada, '') || '" cocok dengan pelanggan "' || v_ada.nama || '" yang dipegang sales '
                || coalesce(v_sales, 'lain') || ', bukan sales SP ini (' || coalesce(v_sales_sp, '—') || ').';
          tindakan := 'Owner/GM memutuskan: pindahkan pelanggannya ke ' || coalesce(v_sales_sp, 'sales SP')
                   || ' di tab Pelanggan, atau ganti sales SP ke ' || coalesce(v_sales, 'pemegangnya')
                   || '. Sesudah itu Vonny bisa meloloskan.';
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
end $$;
revoke all on function public.cek_kelayakan_vonny(bigint, text, text) from public, anon;
grant execute on function public.cek_kelayakan_vonny(bigint, text, text) to authenticated;

create index if not exists customers_kunci_nama_idx on public.customers (public.kunci_nama_pelanggan(nama));
create index if not exists customers_kunci_nama_lama_idx on public.customers (public.kunci_nama_pelanggan(nama_lama))
  where nama_lama is not null;
-- tanpa statistik ekspresi baru, perencana memilih memindai urut id (ORDER BY id LIMIT 1) dan indeks tidak terpakai
analyze public.customers;
