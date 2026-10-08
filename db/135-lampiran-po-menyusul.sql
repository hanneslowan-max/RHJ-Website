-- ═══════════════════════════════════════════════════════════════════════
-- 135 · Keputusan Hannes 8 Okt (pertanyaan 18, sisa temuan keamanan #8): cek Vonny MENAHAN SP yang pelanggannya
--       diisi dari PO yang ditempel menyusul ("Tempelkan PO") selama PO itu belum berlampiran
--
-- Celah (uji DEV berkas 134, L4): SP "PO menyusul" tanpa pelanggan dengan baris di bawah price list → 'menunggu gm'.
-- Sales membuat PO sendiri untuk pelanggan yang punya harga khusus dengan total sama, lalu "Tempelkan PO" →
-- tautkan_po_sp mengisi pelanggan SP dari PO → so_baris_hitung memakai harga khusus pelanggan itu → status pindah ke
-- 'menunggu vonny' (gerbang GM terlewati, komisi ikut pct harga khusus). Penjaganya hanya PO/lampiran yang dilihat
-- Vonny — dan cek_kelayakan_vonny menganggap SP yang sudah tertaut pelanggan langsung "siap".
--
-- Perbaikan:
--  (1) Kolom penanda sales_orders.pelanggan_dari_po (boolean, bawaan false): diisi tautkan_po_sp saat pelanggan SP
--      yang masih kosong diisi dari pelanggan PO yang ditempel. Hanya sistem yang mengisinya — jaga_pelanggan_sp_sales
--      (trigger so_jaga_a_pelanggan, kini juga UPDATE OF pelanggan_dari_po) memaksa false saat INSERT dan menolak
--      perubahan di luar tautkan_po_sp (selain owner/GM/Vonny & tanpa sesi).
--  (2) cek_kelayakan_vonny: SP berpenanda yang PO-nya belum berlampiran → "belum bisa diloloskan", kode lampiran_po,
--      yang membereskan: sales (unggah lampiran di tab Upload PO — RPC lampirkan_po). Layar Double Check menampilkan
--      alasan & tindakan dari server apa adanya; tombol "Nyatakan layak" terkunci.
--  (3) putuskan_vonny_cek: meloloskan SP seperti itu ditolak database (semua peran — owner/GM bisa mengunggah lampiran
--      sendiri). Menahan (Tahan) tetap bisa.
--  (4) Data lama: SP hidup yang belum dikirim dan pelanggannya pernah diisi bersamaan dengan PO yang ditempel
--      (riwayat audit: customer_id & po_id kosong → terisi dalam satu UPDATE) diberi penanda; tanpa trigger
--      (session_replication_role = replica), dicatat di audit_log ('migrasi 135'). DEV: 0 SP.
-- Bila PO menyusul ditempel SETELAH barang dikirim (alur PO menyusul yang biasa), cek Vonny sudah lewat dan tidak
-- diulang — penahanan ini tidak berlaku (dicatat di HANDOFF sebagai sisa).
-- Tidak menyentuh objek EHC/komisi. Tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- (1) penanda
alter table public.sales_orders add column if not exists pelanggan_dari_po boolean not null default false;
comment on column public.sales_orders.pelanggan_dari_po is
  '135: pelanggan SP diisi dari PO yang ditempel menyusul (tautkan_po_sp) — cek Vonny menahan sampai PO berlampiran';

-- jaga_pelanggan_sp_sales: definisi 134/134b + penanda pelanggan_dari_po
create or replace function public.jaga_pelanggan_sp_sales()
returns trigger language plpgsql security definer set search_path = public as $$
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
          using errcode = '42501';
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
        using errcode = '42501';
    end if;
    -- (3) PO hanya ditempel lewat "Tempelkan PO"
    if new.po_id is distinct from old.po_id and not (v_tautkan and old.po_id is null) then
      raise exception
        'PO Surat Pesanan % hanya bisa ditempelkan lewat "Tempelkan PO" (SP yang belum ber-PO). Mengganti atau '
        'melepas PO-nya wewenang owner/GM.', coalesce(old.no_sp, '(baru)')
        using errcode = '42501';
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
          using errcode = '42501';
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
     and public.kunci_nama_pelanggan(new.kepada) is distinct from public.kunci_nama_pelanggan(v_nama)
     and (v_lama is null
          or public.kunci_nama_pelanggan(new.kepada) is distinct from public.kunci_nama_pelanggan(v_lama)) then
    raise exception
      'Kepada pada Surat Pesanan % harus nama pelanggan yang dipilih dari daftar (%). Bila nama pelanggannya baru '
      'diubah, pilih ulang pelanggannya dari daftar; untuk nama lain, kosongkan pilihan pelanggannya lalu isi No. HP & '
      'alamat — Vonny menautkannya saat cek.',
      coalesce(new.no_sp, '(baru)'), v_nama
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_pelanggan_sp_sales() from public, anon, authenticated;
create or replace trigger so_jaga_a_pelanggan
  before insert or update of customer_id, po_id, kepada, pelanggan_dari_po on public.sales_orders
  for each row execute function public.jaga_pelanggan_sp_sales();

-- tautkan_po_sp: definisi 134 + penanda
create or replace function public.tautkan_po_sp(p_so bigint, p_po bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v_so record; v_po record; v_sp numeric; v_nilai numeric; v_lain text;
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

  return 'PO ' || v_po.no_po || ' menempel ke Surat Pesanan ' || v_so.no_sp
         || '. Invoice sudah boleh diterbitkan.';
end $$;

-- (2) cek_kelayakan_vonny: definisi 121 + lampiran PO menyusul
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
      select p.no_po, p.lampiran into v_po_no, v_lampiran from public.purchase_orders p where p.id = s.po_id;
      if coalesce(btrim(v_lampiran), '') = '' then
        kode := 'lampiran_po'; siapa := 'sales';
        pesan := 'Pelanggan SP ini diisi dari PO ' || coalesce(v_po_no, '#' || s.po_id)
              || ' yang ditempel menyusul, tetapi PO itu belum berlampiran.';
        tindakan := 'Sales ' || coalesce(v_sales_sp, '') || ' mengunggah berkas PO customer di tab Upload PO (daftar PO › '
                 || '+ unggah); sesudah itu Vonny memeriksa lampirannya lalu meloloskan.';
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

-- (3) putuskan_vonny_cek: definisi 86 + lampiran PO menyusul
create or replace function public.putuskan_vonny_cek(p_so bigint, p_ok boolean, p_alasan text default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record; v_status text;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh memeriksa kelayakan SP.' using errcode='42501';
  end if;
  if p_ok is null then
    raise exception 'Keputusan cek Vonny wajib: loloskan atau tahan.' using errcode='22023';
  end if;
  select * into v from public.sales_orders where id = p_so for update;
  if v.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002'; end if;
  if v.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', v.no_sp using errcode='22023'; end if;
  v_status := public.status_sp_hitung(p_so);          -- #8 berkas 86: kolom status bisa basi
  if v_status = 'menunggu gm' then
    raise exception 'Surat Pesanan % masih menunggu keputusan GM. Selesaikan harga di GM dulu, baru cek Vonny.', v.no_sp using errcode='22023';
  end if;
  if v_status = 'draft' then
    raise exception 'Surat Pesanan % belum punya baris barang — belum ada yang bisa dicek.', v.no_sp using errcode='22023';
  end if;
  if v.no_surat_jalan is not null or exists (select 1 from public.so_kirim k where k.so_id = p_so) then
    raise exception 'Barang Surat Pesanan % sudah mulai dikirim — keputusan cek Vonny tidak bisa diubah lagi.', v.no_sp using errcode='22023';
  end if;
  -- 135 · pelanggan diisi dari PO yang ditempel menyusul → PO wajib berlampiran sebelum diloloskan (semua peran)
  if p_ok and v.pelanggan_dari_po and v.po_id is not null
     and not exists (select 1 from public.purchase_orders p
                      where p.id = v.po_id and coalesce(btrim(p.lampiran), '') <> '') then
    raise exception 'Surat Pesanan % belum bisa diloloskan: pelanggannya diisi dari PO yang ditempel menyusul, tetapi PO itu '
                    'belum berlampiran. Sales mengunggah berkas PO customer di tab Upload PO dulu.', v.no_sp
      using errcode='22023';
  end if;
  if p_ok is false and coalesce(btrim(p_alasan),'') = '' then
    raise exception 'Menahan SP wajib beralasan supaya sales tahu apa yang perlu dibereskan.' using errcode='22023';
  end if;
  update public.sales_orders
     set vonny_ok = p_ok, vonny_oleh = auth.uid(), vonny_pada = now(),
         vonny_alasan = nullif(btrim(coalesce(p_alasan,'')),''),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_so;
  -- status dihitung ulang trigger so_status_dok (vonny_ok kini didengar, berkas 86)
  return 'Surat Pesanan ' || v.no_sp || (case when p_ok then ' dinyatakan layak diproses.' else ' DITAHAN Vonny.' end);
end $function$;

-- (4) data lama
do $$
declare r record; n int := 0;
begin
  set local session_replication_role = replica;   -- tanpa trigger: status/gugur Vonny/audit otomatis tidak tersentuh
  for r in
    select s.id, to_jsonb(s) as lama
      from public.sales_orders s
     where not s.pelanggan_dari_po and not s.batal and s.po_id is not null and s.customer_id is not null
       and s.no_surat_jalan is null and not exists (select 1 from public.so_kirim k where k.so_id = s.id)
       and exists (select 1 from public.audit_log a
                    where a.tabel = 'sales_orders' and a.aksi = 'UPDATE' and a.baris_id = s.id
                      and (a.sebelum->>'customer_id') is null and (a.sesudah->>'customer_id') is not null
                      and (a.sebelum->>'po_id') is null and (a.sesudah->>'po_id') is not null)
  loop
    update public.sales_orders set pelanggan_dari_po = true where id = r.id;
    insert into public.audit_log (tabel, baris_id, aksi, oleh, oleh_email, pada, sebelum, sesudah)
    select 'sales_orders', r.id, 'UPDATE', null, 'migrasi 135 (pelanggan dari PO menyusul)', now(), r.lama, to_jsonb(s2)
      from public.sales_orders s2 where s2.id = r.id;
    n := n + 1;
  end loop;
  set local session_replication_role = origin;
  raise notice '135: % SP diberi penanda pelanggan_dari_po', n;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass
                  and tgname = 'so_jaga_a_pelanggan' and tgenabled = 'O'
                  and pg_get_triggerdef(oid) like '%pelanggan_dari_po%') then
    raise exception '135: trigger so_jaga_a_pelanggan belum menjaga pelanggan_dari_po';
  end if;
end $$;
