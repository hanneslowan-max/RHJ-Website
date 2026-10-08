-- ═══════════════════════════════════════════════════════════════════════
-- 129 · #60 penawaran: UP, e-mail, TOP (termin pembayaran), diskon per baris
--
-- Keputusan Hannes (7 Okt): (a) diskon PER BARIS (Rp atau %), tanpa diskon total; (b) TOP pilihan Cash / 7 / 14 /
-- 30 / 45 / 60 hari / Lainnya (teks), sales cash-only (Riksa, Michael) terkunci Cash; (c) UP & e-mail terisi otomatis
-- dari data pelanggan, dan e-mail yang belum ada di data pelanggan otomatis disimpan ke sana (juga Nama PIC bila
-- kosong). Penawaran tidak masuk SP/komisi (belum ada konversi penawaran → PO), jadi komisi, HPP, price list, laporan
-- penjualan, dan gerbang GM TIDAK tersentuh; TOP hanya keterangan dokumen (tier cash/tempo tetap di SP, telat 120 hari
-- tetap dari tanggal invoice).
--
-- (1) customers.email (+ CHECK format sederhana). Tidak bocor ke sales lain: tampilan #49 lewat RPC berkolom tetap,
--     tabel customers tetap dijaga RLS cust_baca.
-- (2) quotes.up / email / top (+ CHECK panjang & format). Kosong = tidak dicantumkan di dokumen.
-- (3) quote_lines.diskon (default 0) + diskon_tipe ('rp' | 'persen') dengan CHECK yang SAMA PERSIS dengan po_lines
--     (berkas 106/107): ≥ 0, % ≤ 100, Rp ≤ qty × harga, potongan habis dalam sen, baris berdiskon wajib qty × harga
--     habis dalam sen. Dijaga di tabel (bukan hanya di RPC) karena sales boleh menulis quote_lines lewat REST.
-- (4) trigger quotes_jaga_top: penawaran atas nama sales cash-only hanya boleh TOP Cash (kosong → Cash). Menyala
--     pada INSERT dan UPDATE OF top, sales_rep_id (sesudah quotes_jaga_sales mengisi sales).
-- (5) trigger quotes_kontak_pelanggan (AFTER INSERT, security definer): UP / e-mail penawaran disalin ke Nama PIC /
--     e-mail pelanggan HANYA bila di pelanggan masih kosong (yang sudah ada tidak ditimpa). Lewat trigger supaya
--     berlaku juga untuk Vonny (RLS cust_ubah tidak mencakup Vonny) dan untuk pelanggan baru dari penawaran (#41).
--     Yang boleh menyisipkan penawaran sudah dibatasi quote_tambah (pelanggan_saya) — trigger tidak membuka akses.
-- (6) simpan_penawaran (definisi DEV + kolom baru): menerima p_kepala.up/email/top dan p_baris.diskon/diskon_tipe;
--     pesan galat diskon per baris dibaca dari nama constraint (dulu semua check_violation baris dianggap galat set).
--     #59 (review opsi B): baris barang baru membawa p_baris.usulan_teks → usulkan_produk dipanggil DI DALAM transaksi
--     ini (dulu layar memanggilnya lebih dulu, sehingga penawaran yang gagal disimpan meninggalkan usulan yatim yang
--     muncul di antrean GM). Bagian lain identik. (DEV: perubahan #59 ini dijalankan sebagai "129b_usulan_atomik".)
--
-- Data lama: 15 penawaran DEV — diskon 0, UP/e-mail/TOP kosong → nilai penawaran tidak berubah. Tidak ada DROP.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) e-mail pelanggan ────────────────────────────────────────────────
alter table public.customers add column if not exists email text;
comment on column public.customers.email is '#60 (berkas 129): e-mail pelanggan — terisi dari penawaran bila masih kosong.';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'customers_email_sah' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_email_sah
      check (email is null or (char_length(email) <= 200 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'));
  end if;
end $$;

-- ── (2) kepala penawaran: UP, e-mail, TOP ───────────────────────────────
alter table public.quotes
  add column if not exists up    text,
  add column if not exists email text,
  add column if not exists top   text;
comment on column public.quotes.top is '#60 (berkas 129): termin pembayaran di dokumen (Cash / 7 hari / … / teks lainnya). Hanya keterangan.';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'quotes_kontak_sah' and conrelid = 'public.quotes'::regclass) then
    alter table public.quotes add constraint quotes_kontak_sah check (
      (up is null or (btrim(up) <> '' and char_length(up) <= 120))
      and (top is null or (btrim(top) <> '' and char_length(top) <= 120))
      and (email is null or (char_length(email) <= 200 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')));
  end if;
end $$;

-- ── (3) diskon per baris penawaran (= po_lines) ─────────────────────────
alter table public.quote_lines
  add column if not exists diskon      numeric not null default 0,
  add column if not exists diskon_tipe text    not null default 'rp';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_diskon_tipe_cek' and conrelid = 'public.quote_lines'::regclass) then
    alter table public.quote_lines add constraint quote_lines_diskon_tipe_cek check (diskon_tipe = any (array['rp'::text, 'persen'::text]));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_diskon_min' and conrelid = 'public.quote_lines'::regclass) then
    alter table public.quote_lines add constraint quote_lines_diskon_min check (diskon >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_diskon_maks' and conrelid = 'public.quote_lines'::regclass) then
    alter table public.quote_lines add constraint quote_lines_diskon_maks check (
      case when diskon_tipe = 'persen' then diskon <= 100 else diskon <= qty * harga end);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_diskon_sen' and conrelid = 'public.quote_lines'::regclass) then
    alter table public.quote_lines add constraint quote_lines_diskon_sen check (
      case when diskon_tipe = 'persen' then qty * harga * diskon / 100 = trunc(qty * harga * diskon / 100, 2)
           else diskon = trunc(diskon, 2) end);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_diskon_bruto_sen' and conrelid = 'public.quote_lines'::regclass) then
    alter table public.quote_lines add constraint quote_lines_diskon_bruto_sen check (
      diskon = 0 or qty * harga = trunc(qty * harga, 2));
  end if;
end $$;

-- ── (4) sales cash-only → TOP Cash ──────────────────────────────────────
create or replace function public.quotes_jaga_top()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare v_cash boolean; v_nama text;
begin
  select r.cash_only, r.nama into v_cash, v_nama from public.sales_reps r where r.id = new.sales_rep_id;
  if coalesce(v_cash, false) then
    if new.top is null or btrim(new.top) = '' then
      new.top := 'Cash';
    elsif lower(btrim(new.top)) <> 'cash' then
      raise exception 'Penawaran atas nama % hanya boleh TOP Cash — sales ini wajib cash.', coalesce(v_nama, 'sales ini')
        using errcode = '23514';
    else
      new.top := 'Cash';
    end if;
  end if;
  return new;
end $function$;
create or replace trigger quotes_jaga_top
  before insert or update of top, sales_rep_id on public.quotes
  for each row execute function public.quotes_jaga_top();
revoke all on function public.quotes_jaga_top() from public, anon, authenticated;

-- ── (5) UP / e-mail penawaran → data pelanggan bila masih kosong ────────
create or replace function public.quotes_kontak_pelanggan()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.customer_id is null or (new.up is null and new.email is null) then return null; end if;
  update public.customers c
     set pic   = case when nullif(btrim(coalesce(c.pic, '')), '') is null and new.up is not null then new.up else c.pic end,
         email = case when nullif(btrim(coalesce(c.email, '')), '') is null and new.email is not null then new.email else c.email end
   where c.id = new.customer_id
     and ((nullif(btrim(coalesce(c.pic, '')), '') is null and new.up is not null)
          or (nullif(btrim(coalesce(c.email, '')), '') is null and new.email is not null));
  return null;
end $function$;
create or replace trigger quotes_kontak_pelanggan
  after insert on public.quotes
  for each row execute function public.quotes_kontak_pelanggan();
revoke all on function public.quotes_kontak_pelanggan() from public, anon, authenticated;

-- ── (6) simpan_penawaran menerima kolom baru ────────────────────────────
create or replace function public.simpan_penawaran(p_kepala jsonb, p_baris jsonb)
returns jsonb
language plpgsql
set search_path = public
as $function$
declare
  v_id      bigint;
  v_nomor   text;
  v_tgl     date;
  v_hari    text := nullif(btrim(coalesce(p_kepala->>'berlaku_hari', '')), '');
  v_mode    text := coalesce(nullif(btrim(p_kepala->>'mode_ppn'), ''), 'exclude');
  v_cust    bigint := nullif(p_kepala->>'customer_id', '')::bigint;
  v_rep     bigint := nullif(p_kepala->>'sales_rep_id', '')::bigint;
  v_baru    jsonb := p_kepala->'pelanggan_baru';
  v_up      text := nullif(btrim(coalesce(p_kepala->>'up', '')), '');          -- #60 (berkas 129)
  v_email   text := lower(nullif(btrim(coalesce(p_kepala->>'email', '')), ''));
  v_top     text := nullif(btrim(coalesce(p_kepala->>'top', '')), '');
  v_kepada  text;
  v_kendala text;
  n         int  := 0;
  b         jsonb;
begin
  if not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Anda tidak berhak membuat penawaran.' using errcode = '42501';
  end if;
  if v_mode not in ('exclude','include','non') then
    raise exception 'Mode PPN penawaran tidak dikenal: %.', v_mode;
  end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' or jsonb_array_length(p_baris) = 0 then
    raise exception 'Penawaran tanpa baris tidak disimpan.';
  end if;
  if v_hari is not null and v_hari !~ '^[0-9]{1,4}$' then
    raise exception 'Masa berlaku harus jumlah hari (bilangan bulat), atau kosong = tanpa batas.';
  end if;
  -- #60: e-mail & UP & TOP — diperiksa di sini supaya pesannya jelas (constraint quotes_kontak_sah tetap menjaga)
  if v_email is not null and (char_length(v_email) > 200 or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    raise exception 'E-mail "%" tidak valid — contoh: nama@perusahaan.co.id.', v_email;
  end if;
  if v_up is not null and char_length(v_up) > 120 then
    raise exception 'UP terlalu panjang (maks 120 huruf).';
  end if;
  if v_top is not null and char_length(v_top) > 120 then
    raise exception 'TOP terlalu panjang (maks 120 huruf).';
  end if;
  if v_cust is null and jsonb_typeof(v_baru) = 'object' then
    v_cust := public.buat_pelanggan_baru(v_baru->>'nama', v_baru->>'hp', v_baru->>'lokasi',
                                         case when public.peran_saya() = 'sales' then null else v_rep end);
  end if;
  if v_cust is null then
    raise exception 'Pilih perusahaannya dulu — dari daftar pencarian, atau isi sebagai pelanggan baru.';
  end if;
  select c.nama into v_kepada from public.customers c where c.id = v_cust;
  v_tgl := coalesce(nullif(p_kepala->>'tanggal', '')::date, current_date);
  for coba in 1..10 loop
    v_nomor := public.nomor_penawaran_baru(v_tgl);
    begin
      insert into public.quotes (customer_id, nomor, tanggal, berlaku_hari, kepada, catatan, sales_rep_id, mode_ppn,
                                 up, email, top)
      values (v_cust, v_nomor, v_tgl,
              v_hari::int,
              coalesce(v_kepada, nullif(btrim(p_kepala->>'kepada'), '')),
              nullif(btrim(p_kepala->>'catatan'), ''),
              v_rep, v_mode,
              v_up, v_email, v_top)
      returning id into v_id;
      exit;
    exception when unique_violation then
      get stacked diagnostics v_kendala = constraint_name;
      if v_kendala is distinct from 'quotes_nomor_uniq' then raise; end if;
      v_id := null;
    end;
  end loop;
  if v_id is null then
    raise exception 'Nomor penawaran bentrok terus (10 kali). Coba simpan sekali lagi; bila tetap gagal, hubungi owner.';
  end if;
  for b in select value from jsonb_array_elements(p_baris) loop
    n := n + 1;
    -- #59: barang baru (belum ada di master) diusulkan di dalam transaksi ini — gagal simpan = tidak ada usulan yatim
    if nullif(b->>'product_id', '') is null and nullif(b->>'set_id', '') is null
       and coalesce(jsonb_typeof(b->'set_komponen'), '') <> 'array'
       and nullif(btrim(coalesce(b->>'usulan_teks', '')), '') is not null then
      b := b || jsonb_build_object('product_id', public.usulkan_produk(btrim(b->>'usulan_teks')));
    end if;
    if nullif(b->>'product_id', '') is null and nullif(b->>'set_id', '') is null
       and coalesce(jsonb_typeof(b->'set_komponen'), '') <> 'array' then
      raise exception 'Baris % belum memilih barang atau set.', n;
    end if;
    if nullif(b->>'qty', '') is null or (b->>'qty')::numeric <= 0 then
      raise exception 'Baris %: qty harus lebih dari 0.', n;
    end if;
    if jsonb_typeof(b->'set_komponen') = 'array' and (b->>'qty')::numeric <> trunc((b->>'qty')::numeric) then
      raise exception 'Baris %: jumlah set harus bilangan bulat.', n;
    end if;
    if nullif(b->>'harga', '') is null or (b->>'harga')::numeric < 0 then
      raise exception 'Baris %: harga belum diisi.', n;
    end if;
    begin
      insert into public.quote_lines (quote_id, product_id, set_id, set_komponen, deskripsi, spesifikasi,
                                      qty, satuan, harga, harga_list, urut, diskon, diskon_tipe)
      values (v_id, nullif(b->>'product_id', '')::bigint, nullif(b->>'set_id', '')::bigint,
              case when jsonb_typeof(b->'set_komponen') = 'array' then b->'set_komponen' end,
              coalesce(nullif(btrim(b->>'deskripsi'), ''), '—'), nullif(btrim(b->>'spesifikasi'), ''),
              (b->>'qty')::numeric, coalesce(nullif(b->>'satuan', ''), 'pcs'),
              (b->>'harga')::numeric, nullif(b->>'harga_list', '')::numeric, n,
              coalesce(nullif(b->>'diskon', '')::numeric, 0),                    -- #60 (berkas 129)
              coalesce(nullif(b->>'diskon_tipe', ''), 'rp'));
    exception when check_violation then
      get stacked diagnostics v_kendala = constraint_name;
      raise exception '%', case v_kendala
        when 'quote_lines_diskon_tipe_cek'   then format('Baris %s: tipe diskon harus Rp atau %%.', n)
        when 'quote_lines_diskon_min'        then format('Baris %s: diskon tidak boleh negatif.', n)
        when 'quote_lines_diskon_maks'       then format('Baris %s: diskon melebihi nilai baris (atau lebih dari 100%%).', n)
        when 'quote_lines_diskon_sen'        then format('Baris %s: potongan diskon tidak habis dalam sen — ubah persennya atau pakai diskon Rp (maks 2 angka di belakang koma).', n)
        when 'quote_lines_diskon_bruto_sen'  then format('Baris %s: qty × harga tidak habis dalam sen, tidak bisa diberi diskon.', n)
        else format('Baris %s: set tidak boleh sekaligus menunjuk produk/set master, dan jumlah set harus bulat.', n) end;
    end;
  end loop;
  perform public.catat_spesifikasi_sales(v_id);
  return jsonb_build_object('id', v_id, 'nomor', v_nomor, 'customer_id', v_cust, 'kepada', v_kepada);
end $function$;
