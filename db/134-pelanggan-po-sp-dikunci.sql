-- ═══════════════════════════════════════════════════════════════════════
-- 134 · Temuan keamanan #8: pelanggan & PO Surat Pesanan dikunci sesudah SP dibuat
--
-- Celah (terbukti di DEV, rollback): RLS so_tambah/so_ubah hanya memeriksa pelanggan TUJUAN milik sendiri /
-- belum bertuan (pelanggan_saya), tidak bertanya apakah perubahannya boleh. Lewat REST:
--  · sales PATCH customer_id SP-nya sendiri (juga SP lunas / SP yang ditahan cek Vonny "hp_kosong") ke pelanggannya
--    → aturan No. HP & alamat (122/131) dan penautan Vonny (#37) terlewati, cek_kelayakan_vonny jadi "ok";
--  · SP 'menunggu gm' dipindah ke pelanggan yang punya harga khusus → so_baris_hitung membaca harga khusus pelanggan
--    itu (live lewat s.customer_id) → status 'menunggu vonny', komisi pct harga khusus, gerbang GM terlewati;
--  · INSERT SP tanpa PO dengan customer_id pelanggan harga khusus tetapi Kepada nama orang lain (di layar memilih
--    pelanggan selalu membuat Kepada = nama pelanggan itu; nama diubah = pilihan dilepas);
--  · PATCH po_id langsung (melompati "satu PO satu SP", mode PPN, pemilik PO di tautkan_po_sp), lalu customer_id
--    ikut "pelanggan PO" buatan sendiri;
--  · INSERT SP dari PO lama yang belum tertaut tetapi customer_id diisi pelanggan sendiri;
--  · tautkan_po_sp tidak memeriksa pemilik SP: sales menempelkan PO-nya ke SP sales lain (yang bahkan tidak bisa ia
--    baca), dan pesan selisih total membocorkan nomor & grand total SP sales lain.
-- Tidak ada alur layar yang mengubah customer_id/po_id/kepada SP lewat PATCH (4 PATCH sales_orders di index.html:
-- dokumen kirim, lunas, ehc_dini_ok, keputusan GM). Jalur sah: lengkapi_pelanggan_sp (owner/GM/Vonny),
-- tautkan_po_sp ("Tempelkan PO"), putuskan_ubah ("Minta ubah SP", diputus owner/GM), owner/GM langsung.
--
-- Perbaikan (selain owner/GM/Vonny dan tanpa sesi — Vonny tidak punya PATCH langsung, jalurnya hanya RPC):
--  (1) SP baru dari PO: pelanggan SP = pelanggan PO (kosong → diisi dari PO; PO belum tertaut + pelanggan diisi →
--      ditolak); sales hanya boleh menunjuk PO miliknya (sama dengan tautkan_po_sp gerbang-58).
--  (2) SP baru tanpa PO yang menunjuk pelanggan: Kepada wajib nama pelanggan itu (nama sekarang atau nama lamanya,
--      dibandingkan dengan kunci_nama_pelanggan — PT/CV/tanda baca diabaikan).
--  (3) Sesudah dibuat: customer_id hanya berubah lewat tautkan_po_sp (mengisi yang masih kosong dengan pelanggan
--      PO-nya; bendera transaksi rhj.tautkan_po), po_id hanya ditempel lewat tautkan_po_sp (SP yang belum ber-PO);
--      Kepada SP tanpa PO yang menunjuk pelanggan tetap wajib nama pelanggan itu.
--  (4) tautkan_po_sp: sales hanya untuk SP miliknya — SP sales lain dijawab "tidak ditemukan" (sama dengan SP yang
--      tidak ada), diperiksa sebelum pesan apa pun yang menyebut isi SP.
--  (5) Hasil review adversarial (DEV: migrasi 134b):
--      · Urutan trigger: jaga_po_menyusul (so_jaga_menyusul) dulu menyala lebih awal dan menjawab "PO … milik pelanggan
--        lain" untuk PO sales lain → sales bisa menebak PO mana yang ada & pelanggannya. Trigger ini kini bernama
--        so_jaga_a_pelanggan (menyala sebelum so_jaga_menyusul): PO sales lain selalu "PO #… tidak ditemukan".
--      · "Satu PO satu SP" hanya dijaga tautkan_po_sp — INSERT SP lewat REST bisa memakai PO yang sudah dipakai SP
--        hidup / PO batal, dan SP batal yang dihidupkan lagi bisa menggandakan PO (PO dikirim, ditagih & dikomisikan
--        dua kali). Kini: INSERT (selain owner/GM/Vonny) menolak PO batal / PO yang sudah dipakai (sama dengan daftar
--        po_belum_sp di layar), dan indeks unik so_po_satu_sp (po_id, SP tidak batal) menjaga semua jalur & peran.
--      · Pesan Kepada menyebut "pilih ulang pelanggannya" (nama pelanggan mungkin baru diubah); layar membaca ulang
--        nama pelanggan sebelum nomor SP diambil.
--      · BELUM ditutup (menunggu keputusan Hannes, pertanyaan 9 — ubah nama pelanggan): sales bisa mengganti nama
--        pelanggannya sementara (atau menanam nama_lama) supaya Kepada lolos, lalu mengembalikannya.
-- Tidak diubah: RLS, lengkapi_pelanggan_sp, putuskan_ubah, objek EHC/komisi. Tidak ada data yang diubah; tidak ada
-- objek yang dibuang. SP lama yang Kepada-nya tidak sama dengan nama pelanggannya tidak disentuh (hanya diperiksa
-- bila Kepada / pelanggannya diubah oleh peran selain owner/GM/Vonny).
-- ═══════════════════════════════════════════════════════════════════════

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

-- urutan BEFORE (abjad): sesudah so_a_* / so_audit_ins / so_cash_jaga, SEBELUM so_jaga_menyusul (pemilik PO diperiksa
-- sebelum pesan apa pun yang menyebut pelanggan PO — review 134b) dan sebelum so_y_hanya_gm / so_yy_hp_wajib;
-- pelanggan yang diisi dari PO ikut diperiksa penjaga sesudahnya & RLS. (DEV: nama lama so_jaga_pelanggan diganti.)
do $$ begin
  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass and tgname = 'so_jaga_pelanggan') then
    alter trigger so_jaga_pelanggan on public.sales_orders rename to so_jaga_a_pelanggan;
  end if;
end $$;
create or replace trigger so_jaga_a_pelanggan
  before insert or update of customer_id, po_id, kepada on public.sales_orders
  for each row execute function public.jaga_pelanggan_sp_sales();

-- (5) satu PO satu SP hidup — semua jalur & peran (INSERT, hidupkan SP batal, Tempelkan PO, PATCH owner/GM).
-- SP yang sah tidak pernah berbagi PO: tiap SP wajib = grand total PO (periksa_total_sp).
do $$
declare v text;
begin
  select string_agg(x.no_po || ' (' || x.n || ' SP)', ', ') into v
    from (select s.po_id, p.no_po, count(*) n from public.sales_orders s join public.purchase_orders p on p.id = s.po_id
           where not s.batal group by s.po_id, p.no_po having count(*) > 1) x;
  if v is not null then
    raise exception '134: PO dipakai lebih dari satu SP hidup: % — bereskan dulu (laporkan ke Hannes/GM).', v;
  end if;
end $$;
create unique index if not exists so_po_satu_sp on public.sales_orders (po_id) where po_id is not null and not batal;

-- (4) tautkan_po_sp: definisi DEV sebelum 134 + pemilik SP (sales) + bendera rhj.tautkan_po
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
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_so;
  perform set_config('rhj.tautkan_po', '', true);

  return 'PO ' || v_po.no_po || ' menempel ke Surat Pesanan ' || v_so.no_sp
         || '. Invoice sudah boleh diterbitkan.';
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass
                  and tgname = 'so_jaga_a_pelanggan' and tgenabled = 'O')
     or exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass
                  and tgname = 'so_jaga_pelanggan') then
    raise exception '134: trigger so_jaga_a_pelanggan tidak terpasang tepat satu kali';
  end if;
  if has_function_privilege('anon', 'public.jaga_pelanggan_sp_sales()', 'execute') then
    raise exception '134: jaga_pelanggan_sp_sales masih bisa dijalankan anon';
  end if;
end $$;
