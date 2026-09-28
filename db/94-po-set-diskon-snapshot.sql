-- Berkas 94 (#1 #6 #7): PO — set roda, keterangan, diskon.
--
-- Masalah (terverifikasi di DEV, 28 Sep 2026):
--   (A) #7 SP dari PO berdiskon SELALU ditolak periksa_total_sp: FE (pasangSp) menyalin nett = harga
--       tanpa mengurangi diskon baris → total SP > PO. Contoh nyata: PO 55 (no "4"), 10.000 × 1.000
--       diskon Rp 11 → grand total PO 11.099.988; SP dengan nett = harga pasti selisih Rp 11 + PPN.
--       Alokasi diskon baris SET juga salah presisi: nett = nilai/qty (desimal tak terbatas) dibulatkan
--       diam-diam oleh harga_nett numeric(14,2) → 100001/200 tersimpan 500,01 → 100.002 ≠ 100.001.
--   (B) Diskon tanpa batas atas: persen > 100 atau Rp > qty × harga → nilai baris negatif.
--   (C) #1/#6/#7 minta-ubah PO membuang kolom: putuskan_ubah menghapus lalu menulis ulang po_lines
--       hanya dengan urut, product_id, deskripsi, qty, harga, jenis → baris set kehilangan set_id
--       (ditolak jaga_jenis_baris → PO berisi set tidak bisa diubah), diskon/diskon_tipe/keterangan
--       hilang diam-diam (total PO naik). Usul #7 (menunggu, PO 55) membawa payload tanpa diskon.
--   (D) #1 isi set bebas: tidak ada aturan "1 set roda = 4 roda satu tipe". Pemecahan set ke pcs
--       membaca definisi set SAAT SP DIBUAT, bukan saat PO dibuat. hapusSet (DELETE langsung)
--       ditolak FK po_lines_set_id_fkey dengan galat mentah bila set sudah dipakai PO, dan untuk
--       non-owner RLS membuatnya 0 baris sementara layar menampilkan "Set dihapus.".
--
-- Perubahan (aditif & kompatibel mundur — index.html lama tetap jalan):
-- (1) CHECK po_lines: po_lines_diskon_maks (persen ≤ 100, Rp ≤ qty × harga), po_lines_diskon_sen
--     (potongan habis dalam sen — keputusan #12: tanpa pembulatan, jadi potongan di bawah sen tidak
--     bisa ditiru SP mana pun), po_lines_set_qty_bulat, po_lines_set_bukan_produk. Data DEV: 55 baris,
--     semua lolos (1 berdiskon Rp 11, 0 persen, 0 melewati batas, 0 pecahan di bawah sen).
-- (2) po_lines.set_komponen jsonb = snapshot komponen set saat baris PO disimpan (diisi trigger (6),
--     jadi index.html lama pun ikut mengisinya). Backfill data lama (DEV: 0 baris set).
-- (3) tipe_roda(kode): kunci "tipe" dari kode produk — produk yang hanya beda fungsi (H/M/R/S,
--     OSJ/OSK/OSJB, OSNJ/OSNJB/OSNBK, SPJ/SPK/SPJB, HSUCJ/HSUCJB/HSUCK, OHJ/OHK/OHJB, JCB/KCB/JBCB,
--     TSH/TFH/TSHJB, Hammer 320S/320SR, 420G/420R, 500BPS/500BPR) mendapat kunci sama. Token H/M/R/S
--     hanya dibuang bila ada token berangka sebelumnya ("RHJ R 4" H" → R = bahan karet, tetap).
--     Dibandingkan tanpa spasi, jadi salah ketik "400SR-CB100" tetap setipe dengan "400S-CB 100".
--     Diuji atas semua produk berfungsi di DEV: 264 kunci, 229 berpasangan bersih, 34 berdiri
--     sendiri, 0 kunci melintasi kelompok; satu-satunya bentrok = data Shenpai (id 746 kode H tapi
--     fungsi 'Mati / Rigid') — TIDAK diperbaiki otomatis, dilaporkan.
-- (4) periksa_komposisi_set(komponen jsonb) → NULL = sah, selain itu pesan. Aturan (#1, Hannes):
--     1 set = tepat 4 pcs roda, qty bulat, semua satu kategori + merek + tipe (tipe_roda), fungsi
--     tercatat (Rem / Hidup / Mati), satu produk per fungsi, kombinasi sah: 4 rem, 4 hidup, 4 mati,
--     2 rem + 2 hidup, 2 rem + 2 mati, 2 hidup + 2 mati. Bukan item usulan. harga_nett ≥ 0 & ≤ 2 desimal.
-- (5) Jaring pengaman: constraint trigger DEFERRABLE INITIALLY DEFERRED di product_set_components
--     (komponen diinsert per baris; index.html lama DELETE lalu POST) dan saat set diaktifkan.
-- (6) Trigger po_lines_set_snapshot (BEFORE INSERT/UPDATE): baris set → snapshot dari definisi kini,
--     set wajib aktif & sah; snapshot tidak bisa diubah langsung; putuskan_ubah (rhj.usul='on')
--     membawa snapshot baris lama bila set-nya sama (PO dengan set yang kini nonaktif tetap bisa diubah).
-- (7) RPC simpan_set(p_id, p_kepala, p_komponen) — atomik (dulu 3 request terpisah), dan
--     hapus_set(p_id) — set yang sudah dipakai PO dinonaktifkan dengan pesan jelas, bukan galat FK;
--     non-owner mendapat galat jelas. Keduanya SECURITY INVOKER → hak ikut RLS pset_*/psetc_* yang ada
--     (buat/ubah = owner/gm/staff, hapus = owner). Tidak ada cek peran dobel.
-- (8) po_baris_usul_lengkap (internal): kolom baris yang tidak dikirim diisi dari baris tersimpan
--     (dicocokkan id, lalu urut); snapshot set TIDAK PERNAH diambil dari payload.
--     periksa_baris_po_usul (internal): pesan "Baris N: …" untuk qty/diskon/set.
-- (9) ajukan_ubah (cabang po) & putuskan_ubah (cabang po) memakai (8) → set_id, set_komponen, diskon,
--     diskon_tipe, keterangan terbawa. Usulan lama (#7) & index.html lama ikut tertambal saat
--     diputuskan; nilai_baru usulan yang disetujui disimpan versi lengkapnya. Cabang SP TIDAK diubah.
--     Badan disalin dari pg_get_functiondef terkini (28 Sep 2026) lalu hanya cabang po yang disentuh.
-- (10) Hak: fungsi baru dicabut dari public/anon; helper internal juga dari authenticated.
--
-- Rancangan SP = PO (FE, index.html spBarisDariPo/pecahNettSen): tetap PERSIS, tanpa toleransi.
--   Nilai bersih baris PO T (rumus po_ringkas) dibagi ke qty unit dalam paling banyak 2 baris SP:
--   (q−r) unit @ n dan r unit @ n+1 satuan; satuan = Rp 1 bila T bulat rupiah, selain itu 1 sen.
--   Jumlahnya = T tepat. Selama po_ringkas/periksa_total_sp masih round() per baris, semua nilai baris
--   SP bulat rupiah → round tidak berpengaruh; sesudah pembulatan dihapus (#12), satuan sen tetap
--   tepat. Baris tanpa diskon disalin apa adanya (nett = harga). Baris set: T dialokasikan ke komponen
--   (snapshot) berbobot qty × harga nett, komponen terakhir menyerap sisa, lalu dipecah seperti di atas.
--   Toleransi di periksa_total_sp / kolom diskon di sales_order_lines / membulatkan nett sengaja
--   TIDAK dipilih (menyembunyikan salah hitung / dampak luas / melanggar #12).
--
-- Uji (transaksi rollback, DEV): lihat ringkasan di akhir berkas.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026 (migrasi berkas94_po_set_diskon_snapshot).
-- Belum ke produksi. Urutan di produksi: sesudah berkas 85; berkas ini DULU, baru index.html baru
-- (PO_KOLOM baru memuat po_lines.set_komponen, simpanSet/hapusSet memanggil RPC di sini).
-- Membalik (tidak ada data bisnis yang diubah; kolom set_komponen hanya salinan definisi set):
--   drop trigger po_lines_set_snapshot, psetc_jaga_komposisi, pset_jaga_aktif; drop constraint 4 CHECK
--   di (1); kembalikan ajukan_ubah/putuskan_ubah ke badan sebelum berkas ini (lihat audit/pg_proc
--   sebelum 28 Sep 2026 — cabang po: insert (urut, product_id, deskripsi, qty, harga, jenis)).

-- 1) Batas diskon + qty set bulat + baris set bukan produk
alter table public.po_lines
  add constraint po_lines_diskon_maks check (
    case when diskon_tipe = 'persen' then diskon <= 100 else diskon <= qty * harga end) not valid,
  add constraint po_lines_diskon_sen check (
    case when diskon_tipe = 'persen'
         then qty * harga * diskon / 100 = trunc(qty * harga * diskon / 100, 2)
         else diskon = trunc(diskon, 2) end) not valid,
  add constraint po_lines_set_qty_bulat check (set_id is null or qty = trunc(qty)) not valid,
  add constraint po_lines_set_bukan_produk check (
    set_id is null or (product_id is null and jenis = 'barang')) not valid;
alter table public.po_lines validate constraint po_lines_diskon_maks;
alter table public.po_lines validate constraint po_lines_diskon_sen;
alter table public.po_lines validate constraint po_lines_set_qty_bulat;
alter table public.po_lines validate constraint po_lines_set_bukan_produk;

-- 2) Snapshot komponen set di baris PO
alter table public.po_lines add column if not exists set_komponen jsonb;
comment on column public.po_lines.set_komponen is
  '#1 (berkas 94): snapshot komponen set saat baris PO disimpan [{product_id,qty,harga_nett,urut}]; '
  'dipakai saat SP dibuat (bukan definisi set kini). NULL = bukan baris set. Diisi trigger '
  'po_lines_set_snapshot, tidak bisa diubah langsung.';
-- 2b) backfill data lama (DEV: 0 baris) — SEBELUM trigger (6) dibuat
update public.po_lines l set set_komponen = (
  select jsonb_agg(jsonb_build_object('product_id', c.product_id, 'qty', c.qty,
                                      'harga_nett', c.harga_nett, 'urut', c.urut) order by c.urut, c.id)
    from public.product_set_components c where c.set_id = l.set_id)
 where l.set_id is not null and l.set_komponen is null;

-- 3) Kunci "tipe roda" dari kode (produk yang hanya beda fungsi → kunci sama)
create or replace function public.tipe_roda(p_kode text)
returns text language sql immutable set search_path = public as $$
  -- Token pertama: keluarga kode yang fungsinya ditulis sebagai akhiran/sisipan.
  -- Token H/M/R/S berdiri sendiri = fungsi, tapi hanya bila sebelumnya ada token berangka
  -- ("03 PUR 4" H" → buang H; "RHJ R 4" H" → R = bahan, tetap).
  select nullif(array_to_string(array(
    select case when z.i = 1 then
             case when z.t ~ '^(O[A-Z]*|SP|HSUC)(JB|BK|J|K)$'
                    then regexp_replace(z.t, '(JB|BK|J|K)$', '')          -- OSJ/OSK/OSJB, OSNJ/OSNBK, SPJ, HSUCJ, OHJ…
                  when z.t ~ '^(JB|J|K)CB$' then 'CB'                      -- Osaka SS JCB/KCB/JBCB
                  when z.t ~ '^T[SF]H(JB)?$' then 'TH'                     -- TSH/TFH/TSHJB
                  else regexp_replace(regexp_replace(regexp_replace(z.t,
                         '^([0-9]{3})(SR|S)(-.*)$', '\1S\3'),              -- Hammer 320S-N / 320SR-N
                         '^([0-9]{3})(G|R)(-.*)$', '\1G\3'),               -- Hammer 420G / 420R
                         '^([0-9]{3}BP)(S|R)(-.*)$', '\1S\3') end          -- Hammer 500BPS / 500BPR
           else z.t end
      from (select u.t, u.i,
                   coalesce(bool_or(u.t ~ '[0-9]') over (order by u.i rows between unbounded preceding
                                                          and 1 preceding), false) as ada_angka
              from unnest(regexp_split_to_array(upper(btrim(coalesce(p_kode, ''))), '\s+'))
                   with ordinality u(t, i)) z
     where not (z.t in ('H','M','R','S') and z.ada_angka)
     order by z.i), ' '), '')
$$;
comment on function public.tipe_roda(text) is
  '#1 (berkas 94): kunci tipe roda dari kode — produk yang hanya beda fungsi (rem/hidup/mati) '
  'mendapat kunci sama. Bandingkan tanpa spasi (replace(tipe_roda(kode), '' '', '''')).';

-- 4) Validator komposisi set — NULL = sah, selain itu pesan Bahasa Indonesia. SECURITY INVOKER.
create or replace function public.periksa_komposisi_set(p_komponen jsonb)
returns text language plpgsql stable set search_path = public as $$
declare
  r record;
  v_total numeric := 0; v_rem numeric := 0; v_hidup numeric := 0; v_mati numeric := 0;
  v_acuan text; v_kunci text; v_acuan_ket text;
  v_fungsi jsonb := '{}'::jsonb;
begin
  if p_komponen is null or jsonb_typeof(p_komponen) <> 'array' or jsonb_array_length(p_komponen) = 0 then
    return 'Set harus punya komponen — 1 set roda = 4 pcs roda.';
  end if;
  if exists (select 1 from jsonb_array_elements(p_komponen) x where jsonb_typeof(x) <> 'object') then
    return 'Format komponen set tidak dikenal.';
  end if;
  for r in
    select j.pid, j.qty, j.nett_salah, p.id as ada, p.kode, p.brand, p.kategori, p.fungsi,
           coalesce(p.usulan, false) as usulan, public.tipe_roda(p.kode) as tipe
      from (select nullif(x->>'product_id', '')::bigint as pid,
                   sum(coalesce(nullif(x->>'qty', '')::numeric, 0)) as qty,
                   bool_or(coalesce(nullif(x->>'harga_nett', '')::numeric, 0) < 0
                        or coalesce(nullif(x->>'harga_nett', '')::numeric, 0)
                           <> trunc(coalesce(nullif(x->>'harga_nett', '')::numeric, 0), 2)) as nett_salah
              from jsonb_array_elements(p_komponen) x group by 1) j
      left join public.products p on p.id = j.pid
     order by (p.id is null) desc, p.kode
  loop
    if r.pid is null or r.ada is null then
      return 'Ada komponen yang produknya belum dipilih atau tidak ada di master produk.';
    end if;
    if r.qty <= 0 or r.qty <> trunc(r.qty) then
      return format('Qty %s harus bilangan bulat minimal 1 (sekarang %s).', r.kode, trim_scale(r.qty));
    end if;
    if r.nett_salah then
      return format('Harga nett %s harus ≥ 0 dan paling banyak 2 angka di belakang koma.', r.kode);
    end if;
    if r.usulan then
      return format('%s masih item usulan — sahkan dulu sebelum dipakai di set.', r.kode);
    end if;
    if r.fungsi is null or r.fungsi not in ('Rem / Brake', 'Hidup / Swivel', 'Mati / Rigid') then
      return format('%s belum punya fungsi Rem / Hidup / Mati di master produk — set roda hanya untuk '
                    'roda yang fungsinya tercatat. Isi dulu kolom Fungsi produk itu.', r.kode);
    end if;
    v_kunci := coalesce(r.kategori, '') || '|' || coalesce(r.brand, '') || '|'
               || replace(coalesce(r.tipe, ''), ' ', '');
    if v_acuan is null then
      v_acuan := v_kunci;
      v_acuan_ket := format('%s (%s · %s · tipe %s)', r.kode, coalesce(r.kategori, '?'),
                            coalesce(r.brand, '?'), coalesce(r.tipe, '?'));
    elsif v_kunci <> v_acuan then
      return format('Keempat roda harus satu kategori, satu merek, dan satu tipe — hanya beda fungsi '
                    '(rem/hidup/mati). %s (%s · %s · tipe %s) tidak setipe dengan %s. Kalau sebenarnya '
                    'setipe, periksa penulisan kode/merek/kategori di master produk.',
                    r.kode, coalesce(r.kategori, '?'), coalesce(r.brand, '?'), coalesce(r.tipe, '?'),
                    v_acuan_ket);
    end if;
    if v_fungsi ? r.fungsi then
      return format('Ada dua produk berbeda berfungsi %s (%s dan %s). Satu fungsi = satu produk — '
                    'periksa kolom Fungsi di master produk.', r.fungsi, v_fungsi->>r.fungsi, r.kode);
    end if;
    v_fungsi := v_fungsi || jsonb_build_object(r.fungsi, r.kode);
    if r.fungsi = 'Rem / Brake' then v_rem := r.qty;
    elsif r.fungsi = 'Hidup / Swivel' then v_hidup := r.qty;
    else v_mati := r.qty;
    end if;
    v_total := v_total + r.qty;
  end loop;
  if v_total <> 4 then
    return format('1 set roda = tepat 4 pcs roda; sekarang %s pcs.', trim_scale(v_total));
  end if;
  if (v_rem, v_hidup, v_mati) not in ((4,0,0), (0,4,0), (0,0,4), (2,2,0), (2,0,2), (0,2,2)) then
    return format('Kombinasi %s rem + %s hidup + %s mati tidak sah. Yang sah: 4 rem, 4 hidup, 4 mati, '
                  '2 rem + 2 hidup, 2 rem + 2 mati, atau 2 hidup + 2 mati.',
                  trim_scale(v_rem), trim_scale(v_hidup), trim_scale(v_mati));
  end if;
  return null;
end $$;

-- 5) Jaring pengaman: validasi di akhir transaksi (komponen diinsert per baris)
create or replace function public.jaga_komposisi_set()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ids bigint[]; v_set bigint; v_komp jsonb; v_nama text; v_pesan text;
begin
  if tg_table_name = 'product_sets' then
    v_ids := array[new.id];
  elsif tg_op = 'INSERT' then
    v_ids := array[new.set_id];
  elsif tg_op = 'UPDATE' then
    v_ids := array[new.set_id, old.set_id];
  else
    v_ids := array[old.set_id];
  end if;
  for v_set in select distinct s from unnest(v_ids) s where s is not null loop
    select jsonb_agg(jsonb_build_object('product_id', c.product_id, 'qty', c.qty, 'harga_nett', c.harga_nett)),
           max(s.nama)
      into v_komp, v_nama
      from public.product_set_components c join public.product_sets s on s.id = c.set_id
     where c.set_id = v_set;
    continue when v_komp is null;   -- set kosong/terhapus: tidak bisa dipilih di PO (trigger 6 menolak)
    v_pesan := public.periksa_komposisi_set(v_komp);
    if v_pesan is not null then
      raise exception 'Set "%" tidak sah: %', v_nama, v_pesan;
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists psetc_jaga_komposisi on public.product_set_components;
create constraint trigger psetc_jaga_komposisi
  after insert or update or delete on public.product_set_components
  deferrable initially deferred for each row execute function public.jaga_komposisi_set();
drop trigger if exists pset_jaga_aktif on public.product_sets;
create constraint trigger pset_jaga_aktif
  after update of aktif on public.product_sets
  deferrable initially deferred for each row when (new.aktif and not old.aktif)
  execute function public.jaga_komposisi_set();

-- 6) Snapshot + jaga set di po_lines
create or replace function public.jaga_set_baris_po()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_usul boolean := coalesce(current_setting('rhj.usul', true), '') = 'on';
  v_aktif boolean; v_nama text; v_pesan text;
begin
  if new.set_id is null then
    new.set_komponen := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.set_id is not distinct from old.set_id then
    if new.set_komponen is distinct from old.set_komponen and not v_usul then
      raise exception 'Isi set di baris PO adalah catatan saat PO dibuat dan tidak bisa diubah langsung.';
    end if;
    return new;
  end if;
  -- putuskan_ubah membawa snapshot baris lama bila set-nya sama (po_baris_usul_lengkap membuangnya
  -- bila set_id diganti) → PO dengan set yang kini nonaktif tetap bisa diubah.
  if v_usul and jsonb_typeof(new.set_komponen) = 'array' then
    return new;
  end if;
  select s.aktif, s.nama into v_aktif, v_nama from public.product_sets s where s.id = new.set_id;
  if not found then
    raise exception 'Set #% tidak ditemukan.', new.set_id;
  end if;
  if not v_aktif then
    raise exception 'Set "%" sudah nonaktif — pilih set lain.', v_nama;
  end if;
  select jsonb_agg(jsonb_build_object('product_id', c.product_id, 'qty', c.qty,
                                      'harga_nett', c.harga_nett, 'urut', c.urut) order by c.urut, c.id)
    into new.set_komponen
    from public.product_set_components c where c.set_id = new.set_id;
  if new.set_komponen is null then
    raise exception 'Set "%" belum punya komponen — tidak bisa dipakai di PO.', v_nama;
  end if;
  v_pesan := public.periksa_komposisi_set(new.set_komponen);
  if v_pesan is not null then
    raise exception 'Set "%" tidak sah: % Perbaiki dulu isi setnya (Produk → Set roda).', v_nama, v_pesan;
  end if;
  return new;
end $$;
drop trigger if exists po_lines_set_snapshot on public.po_lines;
create trigger po_lines_set_snapshot before insert or update on public.po_lines
  for each row execute function public.jaga_set_baris_po();

-- 7) RPC set roda (INVOKER → hak ikut RLS pset_*/psetc_*)
create or replace function public.simpan_set(p_id bigint, p_kepala jsonb, p_komponen jsonb)
returns bigint language plpgsql security invoker set search_path = public as $$
declare v_id bigint; v_pesan text; v_nama text := btrim(coalesce(p_kepala->>'nama', ''));
begin
  if v_nama = '' then
    raise exception 'Nama set wajib diisi.';
  end if;
  v_pesan := public.periksa_komposisi_set(p_komponen);
  if v_pesan is not null then
    raise exception '%', v_pesan;
  end if;
  begin
    if p_id is null then
      insert into public.product_sets (nama, kode, kategori, catatan, aktif)
      values (v_nama, nullif(btrim(p_kepala->>'kode'), ''), nullif(btrim(p_kepala->>'kategori'), ''),
              nullif(p_kepala->>'catatan', ''), coalesce((p_kepala->>'aktif')::boolean, true))
      returning id into v_id;
    else
      update public.product_sets
         set nama = v_nama, kode = nullif(btrim(p_kepala->>'kode'), ''),
             kategori = nullif(btrim(p_kepala->>'kategori'), ''),
             catatan = case when p_kepala ? 'catatan' then nullif(p_kepala->>'catatan', '') else catatan end,
             aktif = coalesce((p_kepala->>'aktif')::boolean, aktif),
             diubah_oleh = auth.uid(), diubah_pada = now()
       where id = p_id
      returning id into v_id;
      if v_id is null then
        raise exception 'Set #% tidak ditemukan, atau Anda tidak berwenang mengubah set roda.', p_id;
      end if;
      delete from public.product_set_components where set_id = v_id;
    end if;
    insert into public.product_set_components (set_id, product_id, qty, harga_nett, urut)
    select v_id, (o.x->>'product_id')::bigint, (o.x->>'qty')::numeric,
           coalesce(nullif(o.x->>'harga_nett', '')::numeric, 0), o.i::int
      from jsonb_array_elements(p_komponen) with ordinality o(x, i);
  exception
    when insufficient_privilege then
      raise exception 'Anda tidak berwenang mengubah set roda.' using errcode = '42501';
    when unique_violation then
      raise exception 'Kode set "%" sudah dipakai set lain.', btrim(p_kepala->>'kode');
  end;
  return v_id;
end $$;

create or replace function public.hapus_set(p_id bigint)
returns text language plpgsql security invoker set search_path = public as $$
declare v_nama text; n int;
begin
  select nama into v_nama from public.product_sets where id = p_id;
  if v_nama is null then
    raise exception 'Set #% tidak ditemukan.', p_id;
  end if;
  begin
    delete from public.product_sets where id = p_id;       -- komponen ikut (ON DELETE CASCADE)
    get diagnostics n = row_count;
  exception when foreign_key_violation then
    n := -1;                                                -- sudah dipakai baris PO
  end;
  if n > 0 then
    return format('Set "%s" dihapus.', v_nama);
  end if;
  if n = 0 then
    raise exception 'Hanya owner yang boleh menghapus set. Untuk berhenti memakainya, ubah Status '
                    'set jadi Nonaktif.' using errcode = '42501';
  end if;
  update public.product_sets set aktif = false, diubah_oleh = auth.uid(), diubah_pada = now()
   where id = p_id;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'Anda tidak berwenang menonaktifkan set.' using errcode = '42501';
  end if;
  return format('Set "%s" sudah dipakai di PO, jadi TIDAK dihapus melainkan dinonaktifkan. PO lama '
                'tetap utuh (isi setnya tercatat di PO); set ini tidak bisa dipilih lagi.', v_nama);
end $$;

-- 8) Helper internal minta-ubah PO
create or replace function public.po_baris_usul_lengkap(p_po bigint, p_baris jsonb)
returns jsonb language plpgsql stable set search_path = public as $$
declare x jsonb; b jsonb; hasil jsonb := '[]'::jsonb;
begin
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' then
    return p_baris;
  end if;
  for x in select value from jsonb_array_elements(p_baris) loop
    b := null;
    if jsonb_typeof(x) <> 'object' then
      raise exception 'Format baris usulan tidak dikenal.';
    end if;
    if nullif(x->>'id', '') is not null then
      select to_jsonb(l) into b from public.po_lines l where l.po_id = p_po and l.id = (x->>'id')::bigint;
    end if;
    if b is null and nullif(x->>'urut', '') is not null then
      select to_jsonb(l) into b from public.po_lines l
       where l.po_id = p_po and l.urut = (x->>'urut')::int order by l.id limit 1;
    end if;
    b := coalesce(b, '{}'::jsonb) - 'po_id';
    if (x ? 'set_id') and (x->>'set_id') is distinct from (b->>'set_id') then
      b := b - 'set_komponen';      -- set diganti → snapshot diambil ulang dari definisi (trigger 6)
    end if;
    hasil := hasil || jsonb_build_array(b || (x - 'set_komponen' - 'po_id'));   -- snapshot TAK PERNAH dari payload
  end loop;
  return hasil;
end $$;

create or replace function public.periksa_baris_po_usul(p_baris jsonb)
returns void language plpgsql immutable set search_path = public as $$
declare x jsonb; i int := 0; q numeric; h numeric; d numeric; t text; bruto numeric;
begin
  for x in select value from jsonb_array_elements(coalesce(p_baris, '[]'::jsonb)) loop
    i := i + 1;
    q := nullif(x->>'qty', '')::numeric;
    h := coalesce(nullif(x->>'harga', '')::numeric, 0);
    d := coalesce(nullif(x->>'diskon', '')::numeric, 0);
    t := coalesce(nullif(x->>'diskon_tipe', ''), 'rp');
    if q is null or q <= 0 then
      raise exception 'Baris %: qty harus lebih dari 0.', i;
    end if;
    if nullif(x->>'set_id', '') is not null and q <> trunc(q) then
      raise exception 'Baris %: jumlah set harus bilangan bulat.', i;
    end if;
    if h < 0 then
      raise exception 'Baris %: harga tidak boleh negatif.', i;
    end if;
    if t not in ('rp', 'persen') then
      raise exception 'Baris %: tipe diskon harus Rp atau persen.', i;
    end if;
    if d < 0 then
      raise exception 'Baris %: diskon tidak boleh negatif.', i;
    end if;
    bruto := q * h;
    if t = 'persen' then
      if d > 100 then
        raise exception 'Baris %: diskon % persen melebihi 100 persen.', i, trim_scale(d);
      end if;
      if bruto * d / 100 <> trunc(bruto * d / 100, 2) then
        raise exception 'Baris %: diskon % persen menghasilkan potongan % — tidak habis dalam sen. '
                        'Ubah persennya atau pakai diskon Rp.', i, trim_scale(d), trim_scale(bruto * d / 100);
      end if;
    else
      if d > bruto then
        raise exception 'Baris %: diskon Rp % melebihi nilai baris Rp %.', i, trim_scale(d), trim_scale(bruto);
      end if;
      if d <> trunc(d, 2) then
        raise exception 'Baris %: diskon Rp paling banyak 2 angka di belakang koma.', i;
      end if;
    end if;
    if coalesce(nullif(x->>'jenis', ''), 'barang') = 'barang'
       and nullif(x->>'product_id', '') is null and nullif(x->>'set_id', '') is null then
      raise exception 'Baris %: baris barang harus menunjuk produk atau set.', i;
    end if;
  end loop;
end $$;

-- 9) ajukan_ubah & putuskan_ubah — hanya cabang po yang berubah (badan terkini 28 Sep 2026)
create or replace function public.ajukan_ubah(p_jenis text, p_ref bigint, p_baru jsonb, p_alasan text)
returns bigint language plpgsql security definer set search_path to 'public' as $function$
declare v_lama jsonb; v_id bigint;
begin
  if p_jenis not in ('po','sp') then
    raise exception 'Jenis usulan harus po atau sp.';
  end if;
  if coalesce(btrim(p_alasan), '') = '' or length(btrim(p_alasan)) < 5 then
    raise exception 'Alasan perubahan harus diisi — GM memutuskan dari alasannya, '
                    'bukan dari angkanya saja.';
  end if;

  if p_jenis = 'po' then
    if not public.boleh_input_po() then
      raise exception 'Anda tidak berwenang mengajukan perubahan PO.' using errcode = '42501';
    end if;
    select jsonb_build_object(
             'kepala', to_jsonb(p) - 'dibuat_pada' - 'dibuat_oleh' - 'diubah_pada' - 'diubah_oleh',
             'baris',  coalesce((select jsonb_agg(to_jsonb(l) order by l.urut)
                                   from public.po_lines l where l.po_id = p.id), '[]'::jsonb))
      into v_lama from public.purchase_orders p where p.id = p_ref;
  else
    if not public.boleh_alur_jual() then
      raise exception 'Anda tidak berwenang mengajukan perubahan SP.' using errcode = '42501';
    end if;
    -- Sales hanya boleh mengajukan untuk SP miliknya sendiri.
    if public.peran_saya() = 'sales'
       and not exists (select 1 from public.sales_orders s
                        where s.id = p_ref and s.sales_rep_id = public.sales_rep_saya()) then
      raise exception 'Anda hanya bisa mengajukan perubahan untuk SP milik Anda sendiri.'
        using errcode = '42501';
    end if;
    select jsonb_build_object(
             'kepala', to_jsonb(s) - 'dibuat_pada' - 'dibuat_oleh' - 'diubah_pada' - 'diubah_oleh',
             'baris',  coalesce((select jsonb_agg(to_jsonb(l) order by l.urut)
                                   from public.sales_order_lines l where l.so_id = s.id), '[]'::jsonb))
      into v_lama from public.sales_orders s where s.id = p_ref;
  end if;

  if v_lama is null then
    raise exception 'Dokumen yang mau diubah tidak ditemukan.';
  end if;

  -- #1/#6/#7 (berkas 94): baris PO dilengkapi dari baris tersimpan (set_id, snapshot set, diskon,
  -- diskon_tipe, keterangan) — payload yang tidak membawanya tidak lagi membuang kolom itu.
  if p_jenis = 'po' and jsonb_typeof(p_baru->'baris') = 'array' then
    p_baru := jsonb_set(p_baru, '{baris}', public.po_baris_usul_lengkap(p_ref, p_baru->'baris'));
    perform public.periksa_baris_po_usul(p_baru->'baris');
  end if;

  insert into public.usul_ubah (jenis, ref_id, nilai_lama, nilai_baru, alasan, diajukan_oleh)
  values (p_jenis, p_ref, v_lama, p_baru, btrim(p_alasan), auth.uid())
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'Sudah ada usulan perubahan yang menunggu untuk dokumen ini. '
                  'Tunggu GM memutuskannya dulu.';
end $function$;

create or replace function public.putuskan_ubah(p_id bigint, p_setuju boolean, p_catatan text default null)
returns text language plpgsql security definer set search_path to 'public' as $function$
declare u record; b jsonb; k jsonb; v_beda text;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan usulan perubahan.'
      using errcode = '42501';
  end if;
  select * into u from public.usul_ubah where id = p_id;
  if u is null then raise exception 'Usulan #% tidak ditemukan.', p_id; end if;
  if u.status <> 'menunggu' then
    raise exception 'Usulan #% sudah diputus (%). Keputusan tidak bisa diulang.', p_id, u.status;
  end if;

  if not p_setuju then
    update public.usul_ubah set status = 'ditolak', catatan_gm = p_catatan,
           diputus_oleh = auth.uid(), diputus_pada = now() where id = p_id;
    return 'Usulan #' || p_id || ' ditolak.';
  end if;

  k := u.nilai_baru -> 'kepala';
  b := u.nilai_baru -> 'baris';
  perform set_config('rhj.usul', 'on', true);

  if u.jenis = 'po' then
    update public.purchase_orders p set
      no_po         = coalesce(k->>'no_po', p.no_po),
      tanggal       = coalesce((k->>'tanggal')::date, p.tanggal),
      nama_customer = coalesce(k->>'nama_customer', p.nama_customer),
      alamat        = coalesce(k->>'alamat', p.alamat),
      ppn_kena      = coalesce((k->>'ppn_kena')::boolean, p.ppn_kena),
      sales_rep_id  = coalesce((k->>'sales_rep_id')::bigint, p.sales_rep_id)
     where p.id = u.ref_id;
    if b is not null and jsonb_typeof(b) = 'array' then
      -- #1/#6/#7 (berkas 94): lengkapi dari baris tersimpan SEBELUM dihapus (menambal usulan lama &
      -- index.html lama), lalu tulis ulang dengan SEMUA kolom baris: set_id + snapshot set, diskon,
      -- diskon_tipe, keterangan. Snapshot set dibawa apa adanya (trigger po_lines_set_snapshot).
      b := public.po_baris_usul_lengkap(u.ref_id, b);
      perform public.periksa_baris_po_usul(b);
      delete from public.po_lines where po_id = u.ref_id;
      insert into public.po_lines (po_id, urut, product_id, set_id, set_komponen, deskripsi, keterangan,
                                   qty, harga, diskon, diskon_tipe, jenis)
      select u.ref_id, coalesce(nullif(o.x->>'urut', '')::int, o.i::int),
             nullif(o.x->>'product_id', '')::bigint, nullif(o.x->>'set_id', '')::bigint,
             case when jsonb_typeof(o.x->'set_komponen') = 'array' then o.x->'set_komponen' end,
             nullif(o.x->>'deskripsi', ''), nullif(btrim(o.x->>'keterangan'), ''),
             (o.x->>'qty')::numeric, (o.x->>'harga')::numeric,
             coalesce(nullif(o.x->>'diskon', '')::numeric, 0),
             coalesce(nullif(o.x->>'diskon_tipe', ''), 'rp'),
             coalesce(nullif(o.x->>'jenis', ''), 'barang')
        from jsonb_array_elements(b) with ordinality o(x, i);
    end if;
  else
    update public.sales_orders s set
      kepada   = coalesce(k->>'kepada', s.kepada),
      alamat   = coalesce(k->>'alamat', s.alamat),
      up       = coalesce(k->>'up', s.up),
      telp     = coalesce(k->>'telp', s.telp),
      ppn_kena = coalesce((k->>'ppn_kena')::boolean, s.ppn_kena)
     where s.id = u.ref_id;
    if b is not null and jsonb_typeof(b) = 'array' then
      delete from public.sales_order_lines where so_id = u.ref_id;
      insert into public.sales_order_lines (so_id, urut, product_id, deskripsi, qty,
                                            harga_nett, harga_list, ehc_item, jenis)
      select u.ref_id, (x->>'urut')::int, (x->>'product_id')::bigint, x->>'deskripsi',
             (x->>'qty')::numeric, (x->>'harga_nett')::numeric, (x->>'harga_list')::numeric,
             coalesce((x->>'ehc_item')::numeric, 0), coalesce(x->>'jenis','barang')
        from jsonb_array_elements(b) x;
    end if;
  end if;

  perform set_config('rhj.usul', 'off', true);
  update public.usul_ubah set status = 'disetujui', catatan_gm = p_catatan,
         diputus_oleh = auth.uid(), diputus_pada = now(),
         -- berkas 94: yang tersimpan = yang benar-benar diterapkan (baris PO versi lengkap)
         nilai_baru = case when u.jenis = 'po' and jsonb_typeof(b) = 'array'
                           then jsonb_set(nilai_baru, '{baris}', b) else nilai_baru end
   where id = p_id;

  -- Mengubah PO sesudah SP-nya jadi akan membuat keduanya tidak lagi sama,
  -- padahal berkas 30 mewajibkan totalnya sama persis. Trigger di berkas 30
  -- hanya menyala kalau BARIS SP yang disentuh, jadi perubahan dari sisi PO
  -- lolos begitu saja. Menolaknya di sini tidak bisa: SP-nya baru boleh
  -- diperbaiki sesudah PO-nya betul, jadi kalau PO-nya dikunci sampai SP
  -- cocok, keduanya saling menunggu dan tidak ada yang bisa jalan.
  -- Yang bisa dilakukan: memberi tahu GM di detik ia menyetujui, dengan
  -- nomor SP dan selisihnya — bukan membiarkannya ketahuan sebulan lagi.
  if u.jenis = 'po' then
    select string_agg(v.no_sp || ' (selisih ' ||
                      to_char(v.selisih, 'FM999G999G999G999') || ')', ', ')
      into v_beda from public.sp_beda_po v where v.no_po = (
        select p2.no_po from public.purchase_orders p2 where p2.id = u.ref_id);
    if v_beda is not null then
      return 'Usulan #' || p_id || ' disetujui dan diterapkan. PERHATIAN: '
             || 'Surat Pesanan ' || v_beda || ' sekarang tidak lagi sama dengan '
             || 'PO-nya. SP itu harus ikut diperbaiki — selama belum, angkanya '
             || 'melanggar aturan "grand total SP = PO".';
    end if;
  end if;

  return 'Usulan #' || p_id || ' disetujui dan diterapkan.';
end $function$;

-- 10) Hak (pola berkas 75/84)
revoke execute on function public.tipe_roda(text), public.periksa_komposisi_set(jsonb),
  public.simpan_set(bigint, jsonb, jsonb), public.hapus_set(bigint) from public, anon;
grant execute on function public.tipe_roda(text), public.periksa_komposisi_set(jsonb),
  public.simpan_set(bigint, jsonb, jsonb), public.hapus_set(bigint) to authenticated;
revoke execute on function public.jaga_komposisi_set(), public.jaga_set_baris_po() from public, anon;
revoke execute on function public.po_baris_usul_lengkap(bigint, jsonb), public.periksa_baris_po_usul(jsonb)
  from public, anon, authenticated;   -- internal; dipanggil fungsi SECURITY DEFINER (pemilik postgres)

-- Uji (DEV, transaksi rollback, 28 Sep 2026; sesudah uji: product_sets 0, product_set_components 0,
-- purchase_orders 37, po_lines 55, usul_ubah 6 (#7 & #8 tetap menunggu), sales_orders 33,
-- sales_order_lines 50, audit_log 4693 — sama dengan sebelum uji):
--   T1  owner, PO berdiskon: 3×10.000 −Rp1.000; 7×45.000 −12,5%; biaya 150.000 −Rp25.000;
--       10.000×1.000 −Rp11 (seperti PO 55); 3×10.001 −5%. SP hasil spBarisDariPo (1@9.666 + 2@9.667,
--       7@39.375, 1@125.000, 11@999 + 9.989@1.000, 3@9.501) dalam SATU insert → LOLOS
--       periksa_total_sp (11.594.760 = PO). Kontrol: nett = harga (logika lama) → DITOLAK.
--   T2  owner simpan_set 2H+2M (33/34 @33.333/31.000); PO baris set 3 set −7% (+keterangan) dan
--       2 set −Rp1.001; set_komponen terisi dari definisi (nilai kiriman klien diabaikan; baris bukan
--       set → NULL). SP pecahan (2@30.999 + 4@31.000 + 6@28.830; 3@33.203 + 1@33.204 + 2@30.879 +
--       2@30.880 + baris biasa) → LOLOS (694.093 = PO). simpan_set mengubah harga komponen →
--       snapshot PO TIDAK berubah. Owner UPDATE set_komponen langsung → DITOLAK.
--   T3  vonny ajukan_ubah format LAMA (tanpa id/diskon/set_id/keterangan) pada PO set −7% + keterangan
--       + baris −Rp1.500 + biaya → nilai_baru lengkap; gm putuskan → semua kolom po_lines sama persis,
--       grand total tetap 469.025. Owner hapus_set (dipakai PO) → dinonaktifkan; sales ajukan format
--       BARU (qty set 3→4, 10%, keterangan baru, set_komponen palsu di payload) → gm putuskan LOLOS
--       walau set nonaktif, snapshot lama terbawa, grand 558.935 (dihitung ulang manual: cocok).
--       Payload 150% / Rp > bruto / set 2,5 → DITOLAK "Baris N: …".
--       gm putuskan_ubah(7) (usul nyata PO 55, rollback) → diskon Rp 11 tetap, grand 11.099.988.
--   T4  simpan_set DITOLAK dengan pesan jelas: 3R+1H, 5 pcs, PUR+CB (tipe beda), Hospital+Roda,
--       fungsi NULL (789), travelator (bukan roda), Shenpai 746+427 (dua "Mati"), qty 1,5,
--       harga_nett 3 desimal, produk kosong, tanpa komponen. INSERT langsung komponen 3R+1H →
--       DITOLAK saat set constraints immediate. Aktivasi set yang jadi tidak sah (fungsi produk diubah)
--       → DITOLAK.
--   T5  DITERIMA: 4R, 4H, 2R+2H, 2H+2M, 2R+2M, OSJ+OSK, OSJB+OSK, 320S-N+320SR-N, HSUCJ+HSUCJB,
--       TSH+TFH, 400S-CB 100 + 400SR-CB100, komponen ganda (digabung per produk).
--   T6  owner hapus_set belum dipakai → terhapus; gm hapus_set → DITOLAK 42501 "Hanya owner…";
--       gm simpan_set ubah → LOLOS; sales/vonny simpan_set → DITOLAK; sales & vonny INSERT PO dengan set
--       → snapshot terisi; PO baru dengan set nonaktif → DITOLAK; baris set + product_id → DITOLAK.
--   T7  CHECK langsung: persen 101, Rp > bruto, Rp 0,001, 1 × 1.234,57 × 7% (potongan 86,4199),
--       set qty 1,5 → DITOLAK; diskon = bruto (nilai 0) → boleh. Validasi data lama (55 baris) lolos.
--   T8  has_function_privilege: anon = false untuk semua fungsi baru; authenticated = false untuk
--       po_baris_usul_lengkap & periksa_baris_po_usul. (Fungsi trigger jaga_* tetap EXECUTE untuk
--       authenticated seperti pola berkas 84 — tidak bisa dipanggil lewat RPC; dicek: trigger tetap
--       jalan walau EXECUTE authenticated dicabut, jadi boleh dicabut kelak bila linter mengganggu.)
