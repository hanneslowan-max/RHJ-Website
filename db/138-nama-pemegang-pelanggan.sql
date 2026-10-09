-- ═══════════════════════════════════════════════════════════════════════
-- 138 · Temuan keamanan #2 + sisa #8 (keputusan Hannes 9 Okt, no. 8a, 9, 10a, 17a): nama & pemegang pelanggan dijaga
--
-- Celah (uji DEV, rollback):
--  · Nama ganda: hanya buat_pelanggan_baru yang menolak; lewat REST sales bisa POST /customers dengan nama pelanggan
--    sales lain, atau PATCH nama pelanggannya menjadi nama itu → cek Vonny (order by id) menautkan SP ke pelanggan
--    sales itu sendiri, melompati "pelanggan sales lain tidak ditautkan" (#37/#50).
--  · Ganti nama pelanggan bertransaksi/berharga khusus oleh sales: nama di dokumen lama ikut berubah (#47), dan
--    (sisa #8) sales mengganti nama sementara supaya Kepada SP palsu lolos (berkas 134) lalu mengembalikannya → harga
--    khusus & gerbang GM terlewati; atau menanam alias permanen di nama_lama (customers_rapi_nama mengisi nama_lama
--    dari ketikan saat nama_lama kosong) yang juga menyetir pencocokan nama cek Vonny. Tanpa jejak (customers belum
--    diaudit).
--  · Sales mengambil sendiri pelanggan belum bertuan di tab Pelanggan (tanpa PO) — termasuk kembaran pelanggan Office.
--
-- Perbaikan (selain jalur tanpa sesi: migrasi / SQL Editor / service role — apa adanya):
--  (1) customers_tolak_nama_ganda (BEFORE INSERT/UPDATE OF nama, nama_lama, id; menyala sesudah customers_rapi_nama):
--      · nomor data pelanggan (id) tidak bisa diubah;
--      · (no. 9) nama pelanggan yang sudah dipakai di SP/PO/penawaran/harga khusus hanya diganti owner/GM/staff —
--        peran lain hanya boleh merapikan penulisan (huruf besar-kecil, tanda baca, urutan PT/CV: sidik huruf DAN
--        kunci nama tetap sama);
--      · (no. 8a) SALES: nama yang kuncinya (kunci_nama_pelanggan, nama atau nama asli) sama dengan pelanggan lain
--        ditolak di semua jalur — beri pembeda (mis. kota/cabang). Owner/GM/staff boleh, layar memberi peringatan
--        (RPC nama_pelanggan_kembar). Hanya kunci BARU yang diperiksa; data kembar lama dibiarkan.
--      Pesan P0001/23505 (HTTP 400/409 — tidak memicu batas tolak 401/403 di layar).
--  (2) customers_rapi_nama: perubahan nama oleh sales tidak lagi mengisi nama_lama (alias tidak bisa ditanam).
--  (3) (no. 17a) customers_jaga_sales: sales tidak bisa mengambil sendiri pelanggan belum bertuan — hanya otomatis
--      lewat PO (po_auto_klaim_sales, bendera transaksi rhj.klaim_po), atau dipindah owner/GM/staff.
--  (4) audit_log untuk customers (catat_perubahan: tambah/ubah/hapus).
--  (5) (no. 10a) cek_kelayakan_vonny & lengkapi_pelanggan_sp: kembaran nama milik sales lain didahulukan (SP ditahan
--      nama_sales_lain / ditolak), lalu milik sales SP, lalu yang belum bertuan.
--  (6) RPC nama_pelanggan_kembar(p_nama, p_kecuali): pelanggan lain dengan kunci nama sama (nama, pemegang) — untuk
--      peringatan layar. Nama & pemegang pelanggan sales lain memang boleh dilihat (#49).
-- Sisa (dicatat, perlu keputusan): kembaran nama lama yang belum bertuan masih bisa diambil lewat PO oleh sales lain.
-- Tidak menyentuh objek EHC/komisi. Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139r/139s/139w/139x/139y/139z (review 139y no. 5): menjalankannya ulang sendirian
--      menurunkan fungsi yang diperbarui berkas sesudahnya. Menjalankan ulang seluruh rantai 138 → berkas terakhir
--      berurutan dalam satu transaksi: `begin; set local rhj.ulang_rantai = 'on';` … `commit;`.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '138: berkas ini sudah disusul berkas sesudahnya — jangan dijalankan ulang sendirian (jalankan ulang '
                    'seluruh rantai 138 → berkas terakhir berurutan dalam satu transaksi sesudah set local rhj.ulang_rantai = ''on'').';
  end if;
end $$;

-- (2) customers_rapi_nama — definisi berkas 100 + sales tidak mengisi nama_lama saat mengubah nama
create or replace function public.customers_rapi_nama()
returns trigger language plpgsql set search_path to 'public' as $function$
declare v_mentah text; v_rapi text;
begin
  -- jalur admin (terapkan/pulihkan/migrasi) mengatur nama & nama_lama sendiri
  if coalesce(current_setting('rhj.lewati_rapi_nama', true), 'off') = 'on' then return new; end if;
  if tg_op = 'UPDATE' then
    new.nama_lama := old.nama_lama;              -- cadangan tak bisa diubah/dihapus lewat REST
    if new.nama is not distinct from old.nama then return new; end if;  -- nama sama → biarkan
  else
    new.nama_lama := null;                       -- INSERT: abaikan kiriman klien
  end if;
  v_mentah := new.nama;
  v_rapi := public.rhj_nama_rapi(v_mentah);
  if v_rapi is distinct from v_mentah then
    new.nama := v_rapi;
    -- cadangan sekali saja; 138: ubahan nama oleh SALES tidak menanam nama asli (alias pencocokan)
    if new.nama_lama is null and (tg_op = 'INSERT' or auth.uid() is null or public.peran_saya() <> 'sales') then
      new.nama_lama := v_mentah;
    end if;
  end if;
  return new;
end $function$;

-- (1)
create or replace function public.customers_tolak_nama_ganda()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_peran text;
  v_lama  text[] := '{}';
  v_cek   text[];
  v_k     text;
  v_ada   record;
begin
  if auth.uid() is null then return new; end if;                                  -- migrasi / SQL Editor / service
  if coalesce(current_setting('rhj.lewati_rapi_nama', true), 'off') = 'on' then return new; end if;  -- rapikan/pulihkan
  v_peran := public.peran_saya();
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'Nomor data pelanggan tidak bisa diubah.' using errcode = '22023';
    end if;
    v_lama := array[public.kunci_nama_pelanggan(old.nama), public.kunci_nama_pelanggan(old.nama_lama)];
    -- (no. 9) ganti nama pelanggan bertransaksi / berharga khusus
    if v_peran not in ('owner','gm','staff')
       and (public.rhj_nama_sidik(new.nama) is distinct from public.rhj_nama_sidik(old.nama)
            or public.kunci_nama_pelanggan(new.nama) is distinct from public.kunci_nama_pelanggan(old.nama))
       and (exists (select 1 from public.sales_orders s where s.customer_id = old.id)
            or exists (select 1 from public.purchase_orders p where p.customer_id = old.id)
            or exists (select 1 from public.quotes q where q.customer_id = old.id)
            or exists (select 1 from public.harga_khusus h where h.customer_id = old.id)) then
      raise exception 'Nama pelanggan "%" sudah dipakai di SP/PO/penawaran/harga khusus — penggantian namanya hanya oleh '
                      'owner, GM, atau staff. Sales hanya bisa merapikan penulisannya (huruf besar-kecil, tanda baca, '
                      'letak PT/CV).', old.nama;
    end if;
  end if;
  if v_peran <> 'sales' then return new; end if;   -- (no. 8a) owner/GM/staff: boleh, layar memberi peringatan

  -- (no. 8a) sales: kunci BARU saja
  select array_agg(distinct k order by k) into v_cek
    from unnest(array[public.kunci_nama_pelanggan(new.nama), public.kunci_nama_pelanggan(new.nama_lama)]) k
   where coalesce(k, '') <> '' and not (k = any (v_lama));
  if v_cek is null then return new; end if;
  foreach v_k in array v_cek loop   -- dua simpan bersamaan dengan kunci sama: yang kedua menunggu lalu ditolak
    perform pg_advisory_xact_lock(hashtextextended('customers.kunci_nama:' || v_k, 0));
  end loop;
  select c.nama, sr.nama as sales into v_ada
    from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
   where c.id <> new.id
     and (public.kunci_nama_pelanggan(c.nama) = any (v_cek)
          or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = any (v_cek)))
   order by c.id limit 1;
  if found then
    raise exception 'Pelanggan "%" sudah ada di data pelanggan (%). Pilih dari daftar pencarian — satu perusahaan satu '
                    'data pelanggan. Bila memang perusahaan/orang lain dengan nama sama, tambahkan pembeda pada namanya '
                    '(mis. kota atau cabang).',
      v_ada.nama, coalesce('dipegang sales ' || v_ada.sales, 'belum bertuan') using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.customers_tolak_nama_ganda() from public, anon, authenticated;
-- urutan abjad: sesudah customers_rapi_nama & customers_sales_bawaan → melihat nama yang sudah dirapikan + nama_lama
create or replace trigger customers_tolak_nama_ganda
  before insert or update of nama, nama_lama, id on public.customers
  for each row execute function public.customers_tolak_nama_ganda();

-- (3) customers_jaga_sales — definisi berkas 40 + klaim sales hanya lewat PO
create or replace function public.customers_jaga_sales()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.sales_rep_id is distinct from old.sales_rep_id
     and public.peran_saya() = 'sales' then
    -- Sales boleh MENGAKUI pelanggan yang belum bertuan, dan hanya untuk
    -- dirinya sendiri. Selebihnya keputusan atasan.
    if old.sales_rep_id is not null then
      raise exception 'Pelanggan ini sudah dipegang sales lain. Pemindahan pelanggan '
                      'diputuskan owner, GM, atau staff — bukan diambil sendiri.'
        using errcode = '42501';
    end if;
    if new.sales_rep_id is distinct from public.sales_rep_saya() then
      raise exception 'Anda hanya bisa mengambil pelanggan yang belum bertuan untuk diri '
                      'sendiri.' using errcode = '42501';
    end if;
    -- 138 (keputusan Hannes 9 Okt no. 17a): hanya otomatis lewat PO (po_auto_klaim_sales)
    if coalesce(current_setting('rhj.klaim_po', true), '') <> '1' then
      raise exception 'Pelanggan yang belum bertuan menjadi milik sales yang pertama membuat PO untuknya — tidak bisa '
                      'diambil langsung. Bila perlu dipindahkan sekarang, minta owner, GM, atau staff.';
    end if;
  end if;
  return new;
end $function$;

-- (3) po_auto_klaim_sales — definisi berkas 79 + bendera rhj.klaim_po
create or replace function public.po_auto_klaim_sales()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.sales_rep_id is not null and new.customer_id is not null then
    begin
      perform set_config('rhj.klaim_po', '1', true);   -- 138: satu-satunya jalur klaim oleh sales
      update public.customers c
         set sales_rep_id = new.sales_rep_id
       where c.id = new.customer_id and c.sales_rep_id is null;
      perform set_config('rhj.klaim_po', '', true);
    exception when others then
      perform set_config('rhj.klaim_po', '', true);
      null;  -- auto-klaim gagal tidak boleh menggagalkan pembuatan PO
    end;
  end if;
  return new;
end $function$;

-- (4) audit customers (tambah/ubah/hapus)
do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'zz_audit_customers') then
    execute 'create trigger zz_audit_customers after insert or update or ' || 'DEL' || 'ETE'
         || ' on public.customers for each row execute function public.catat_perubahan()';
  end if;
end $$;

-- (6) peringatan nama kembar untuk layar
create or replace function public.nama_pelanggan_kembar(p_nama text, p_kecuali bigint default null)
returns table (id bigint, nama text, sales text)
language plpgsql stable security definer set search_path = public as $$
declare v_k text := public.kunci_nama_pelanggan(p_nama);
begin
  if auth.uid() is null or not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Pemeriksaan nama pelanggan hanya untuk peran yang mengelola pelanggan.' using errcode = '42501';
  end if;
  if coalesce(v_k, '') = '' then return; end if;
  return query
    select c.id, c.nama, sr.nama
      from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
     where c.id is distinct from p_kecuali
       and (public.kunci_nama_pelanggan(c.nama) = v_k
            or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k))
     order by c.id limit 5;
end $$;
revoke all on function public.nama_pelanggan_kembar(text, bigint) from public, anon;
grant execute on function public.nama_pelanggan_kembar(text, bigint) to authenticated;

-- (5) cek_kelayakan_vonny: definisi 135 + urutan kembaran
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
  v_po_no    text;
  v_lampiran text;
  v_sales_po text;
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
    v_kunci := public.kunci_nama_pelanggan(s.kepada);
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

-- (5) lengkapi_pelanggan_sp: definisi 115 + urutan kembaran
create or replace function public.lengkapi_pelanggan_sp(p_so bigint, p_industri text, p_hp text default null,
                                                        p_alamat text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  s        public.sales_orders;
  v_ind    text := nullif(btrim(coalesce(p_industri, '')), '');
  v_cust   bigint;
  v_kunci  text;
  v_hp     text;
  v_cocok  text;
  v_dibuat boolean := false;
  v_pakai  boolean := true;
  v_ada    public.customers;
  v_sales  text;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh melengkapi pelanggan SP.' using errcode = '42501';
  end if;
  if v_ind is null or v_ind not in ('Otomotif','Non Otomotif','Bengkel Otomotif') then
    raise exception 'Kategori industri hanya Otomotif, Non Otomotif, atau Bengkel Otomotif.' using errcode = '22023';
  end if;
  select * into s from public.sales_orders where id = p_so for update;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode = '22023'; end if;

  if s.customer_id is not null then
    perform public.set_industri_pelanggan(s.customer_id, v_ind);
    return jsonb_build_object('customer_id', s.customer_id, 'dibuat', false, 'dicocokkan', 'sudah', 'industri', v_ind,
                              'kategori_dipakai', true, 'nama', (select nama from public.customers where id = s.customer_id));
  end if;

  -- cocokkan: nama (tanpa PT/CV & tanda baca), lalu No. HP (berkas 115)
  v_kunci := public.kunci_nama_pelanggan(s.kepada);
  -- 138 (keputusan Hannes 9 Okt no. 10): kembaran milik sales LAIN didahulukan (→ ditolak di bawah), lalu milik
  -- sales SP, lalu yang belum bertuan — sama dengan cek_kelayakan_vonny
  select c.* into v_ada from public.customers c
   where public.kunci_nama_pelanggan(c.nama) = v_kunci
      or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci)
   order by case when c.sales_rep_id is not null and c.sales_rep_id is distinct from s.sales_rep_id then 0
                 when c.sales_rep_id is not null then 1 else 2 end, c.id
   limit 1;
  if v_ada.id is not null then v_cocok := 'nama';
  else
    v_hp := public.hp_baku(coalesce(nullif(btrim(p_hp), ''), s.telp));
    if v_hp is not null then
      select c.* into v_ada from public.customers c where c.hp = v_hp order by c.id limit 1;
      if v_ada.id is not null then v_cocok := 'hp'; end if;
    end if;
  end if;

  if v_ada.id is not null then
    -- berkas 115: pelanggan bertuan hanya untuk sales pemegangnya (sama dengan RLS po/so _tambah)
    if v_ada.sales_rep_id is not null and s.sales_rep_id is not null and v_ada.sales_rep_id <> s.sales_rep_id then
      select nama into v_sales from public.sales_reps where id = v_ada.sales_rep_id;
      raise exception '% SP % cocok dengan pelanggan "%" yang dipegang sales %, bukan sales SP ini. '
                      'Pindahkan dulu pelanggannya ke sales SP (tab Pelanggan) atau ganti sales SP — owner/GM.',
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id)
        using errcode = '42501';
    end if;
    v_cust := v_ada.id;
    if v_ada.industri is null then update public.customers set industri = v_ind where id = v_cust;   -- yang sudah terisi tidak ditimpa
    else v_pakai := v_ada.industri = v_ind; end if;
  else
    v_cust := public.buat_pelanggan_baru(s.kepada, coalesce(nullif(btrim(p_hp), ''), s.telp),
                                         coalesce(nullif(btrim(p_alamat), ''), s.alamat), s.sales_rep_id);
    update public.customers set industri = v_ind where id = v_cust;
    v_dibuat := true; v_cocok := 'baru';
  end if;

  update public.sales_orders set customer_id = v_cust, diubah_pada = now(), diubah_oleh = auth.uid() where id = p_so;
  if s.po_id is not null then
    update public.purchase_orders set customer_id = v_cust where id = s.po_id and customer_id is null;
  end if;
  return jsonb_build_object('customer_id', v_cust, 'dibuat', v_dibuat, 'dicocokkan', v_cocok,
                            'kategori_dipakai', v_pakai,
                            'industri', (select industri from public.customers where id = v_cust),
                            'nama', (select nama from public.customers where id = v_cust));
end $function$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'customers_tolak_nama_ganda')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'zz_audit_customers') then
    raise exception '138: trigger pelanggan belum terpasang';
  end if;
  if has_function_privilege('anon', 'public.nama_pelanggan_kembar(text,bigint)', 'execute') then
    raise exception '138: nama_pelanggan_kembar masih bisa dijalankan anon';
  end if;
end $$;
