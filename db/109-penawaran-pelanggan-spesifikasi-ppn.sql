-- ═══════════════════════════════════════════════════════════════════════
-- 109 · Penawaran (#40 #41 #42 #47 #48)
--
--  #41  Penawaran untuk pelanggan BARU: simpan_penawaran menerima
--       p_kepala.pelanggan_baru {nama, hp, lokasi}. Pelanggannya dibuat di master
--       (fungsi buat_pelanggan_baru — dipakai juga form PO, #29) dalam transaksi
--       yang sama. Wajib: nama, alamat (lokasi), HP; sales PIC = sales penawaran.
--  #48  Pelanggan bertuan HANYA bisa ditawarkan atas nama sales pemegangnya —
--       sekarang untuk SEMUA peran (dulu owner/GM/staff boleh beda).
--  #47  quotes.kepada diisi dari customers.nama (sudah dirapikan: PT/CV di depan),
--       bukan teks kiriman layar.
--  #40  products.spesifikasi (master, diubah owner/GM/staff/Vonny lewat RLS produk)
--       + spesifikasi_sales: spesifikasi terakhir yang dipakai tiap sales per produk,
--       dicatat otomatis setiap penawaran disimpan. Hanya lewat fungsi (tanpa
--       policy tulis untuk klien).
--  #42  quotes.mode_ppn: exclude (harga belum termasuk PPN, default & perilaku lama)
--       / include (harga sudah termasuk PPN) / non (tanpa PPN).
--
-- Tidak ada data yang dihapus atau ditimpa: hanya kolom/tabel/fungsi baru dan
-- penggantian definisi fungsi.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) #40 master spesifikasi produk ────────────────────────────────────
alter table public.products add column if not exists spesifikasi text;
comment on column public.products.spesifikasi is
  '#40 (berkas 109): spesifikasi baku produk — isian awal kolom spesifikasi di penawaran.';

-- ── (2) #40 spesifikasi terakhir per sales per produk ────────────────────
create table if not exists public.spesifikasi_sales (
  product_id   bigint not null references public.products(id) on delete cascade,
  sales_rep_id bigint not null references public.sales_reps(id) on delete cascade,
  spesifikasi  text   not null check (btrim(spesifikasi) <> ''),
  quote_id     bigint references public.quotes(id) on delete set null,   -- penawaran yang terakhir memakainya
  diubah_pada  timestamptz not null default now(),
  diubah_oleh  uuid references auth.users(id),
  primary key (product_id, sales_rep_id)
);
comment on table public.spesifikasi_sales is
  '#40 (berkas 109): spesifikasi terakhir yang dipakai sales untuk sebuah produk di penawaran. '
  'Ditulis hanya oleh catat_spesifikasi_sales() (dipanggil simpan_penawaran).';
alter table public.spesifikasi_sales enable row level security;
drop policy if exists spek_sales_baca on public.spesifikasi_sales;
create policy spek_sales_baca on public.spesifikasi_sales for select to authenticated
  using (public.peran_saya() in ('owner','gm','staff','vonny')
         or (public.peran_saya() = 'sales' and sales_rep_id = public.sales_rep_saya()));
revoke all on public.spesifikasi_sales from anon, authenticated;
grant select on public.spesifikasi_sales to authenticated;

-- ── (3) #42 mode PPN penawaran ───────────────────────────────────────────
alter table public.quotes add column if not exists mode_ppn text not null default 'exclude';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'quotes_mode_ppn_cek') then
    alter table public.quotes add constraint quotes_mode_ppn_cek
      check (mode_ppn in ('exclude','include','non'));
  end if;
end $$;
comment on column public.quotes.mode_ppn is
  '#42 (berkas 109): exclude = harga belum termasuk PPN 11% (PPN ditambahkan); '
  'include = harga sudah termasuk PPN (DPP = total ÷ 1,11; PPN = total − DPP); non = tanpa PPN.';

-- ── (4) #41 #29 pembuat pelanggan baru ───────────────────────────────────
-- Kunci pencocokan nama: kata alfanumerik tanpa badan usaha — sama dengan
-- cek_pemilik_pelanggan (berkas 105), supaya "Surya Panel, PT" = "PT Surya Panel".
create or replace function public.kunci_nama_pelanggan(p text)
returns text language sql immutable set search_path = public as $$
  select coalesce(string_agg(k, ' ' order by n), '')
    from regexp_split_to_table(btrim(regexp_replace(lower(coalesce(p, '')), '[^[:alnum:]]+', ' ', 'g')), ' ')
         with ordinality as s(k, n)
   where k <> '' and k not in ('pt','cv','ud','pd','tb','tbk','toko')
$$;

create or replace function public.buat_pelanggan_baru(p_nama text, p_hp text, p_lokasi text, p_sales_rep bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_peran text := public.peran_saya();
  v_rep   bigint;
  v_hp    text := regexp_replace(coalesce(p_hp, ''), '\D', '', 'g');
  v_nama  text := btrim(coalesce(p_nama, ''));
  v_lok   text := btrim(coalesce(p_lokasi, ''));
  v_kunci text;
  v_ada   record;
  v_id    bigint;
begin
  if v_peran not in ('owner','gm','staff','sales','vonny') then
    raise exception 'Anda tidak berhak menambah pelanggan baru.' using errcode = '42501';
  end if;
  if v_nama = '' then raise exception 'Nama pelanggan baru wajib diisi.'; end if;
  if v_lok = ''  then raise exception 'Alamat pelanggan baru wajib diisi.'; end if;
  -- HP: bentuk baku 62…, sama dengan hpNormal() di layar
  if v_hp = '' then raise exception 'Nomor HP pelanggan baru wajib diisi.'; end if;
  if left(v_hp, 1) = '0' then v_hp := '62' || substr(v_hp, 2);
  elsif left(v_hp, 1) = '8' then v_hp := '62' || v_hp; end if;
  if v_hp !~ '^[1-9][0-9]{8,15}$' then
    raise exception 'Nomor HP "%" tidak valid — isi 9 sampai 16 angka, mis. 0812xxxxxxx.', p_hp;
  end if;

  -- Sales PIC: sales = dirinya sendiri; peran lain wajib memilih sales yang aktif.
  if v_peran = 'sales' then
    v_rep := public.sales_rep_saya();
    if v_rep is null then
      raise exception 'Akun Anda belum ditautkan ke nama sales — minta owner mengisi "Masuk sebagai" di tab Pengguna.';
    end if;
    if p_sales_rep is not null and p_sales_rep is distinct from v_rep then
      raise exception 'Sales hanya bisa menambah pelanggan baru untuk dirinya sendiri.' using errcode = '42501';
    end if;
  else
    v_rep := p_sales_rep;
    if v_rep is null then raise exception 'Pilih sales PIC untuk pelanggan baru ini.'; end if;
    if not exists (select 1 from public.sales_reps where id = v_rep and aktif) then
      raise exception 'Sales PIC yang dipilih tidak ada atau sudah nonaktif.';
    end if;
  end if;

  -- Dobel nama (setelah buang tanda baca & PT/CV) atau dobel HP → pakai yang sudah ada.
  v_kunci := public.kunci_nama_pelanggan(v_nama);
  if char_length(v_kunci) < 2 then raise exception 'Nama pelanggan baru terlalu pendek.'; end if;
  select c.nama, sr.nama as sales into v_ada
    from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
   where public.kunci_nama_pelanggan(c.nama) = v_kunci
      or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci)
   order by c.id limit 1;
  if found then
    raise exception 'Pelanggan "%" sudah ada di master (%). Pilih dari daftar pencarian, jangan dibuat baru.',
      v_ada.nama, coalesce('dipegang sales ' || v_ada.sales, 'belum bertuan');
  end if;
  select c.nama, sr.nama as sales into v_ada
    from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
   where c.hp = v_hp limit 1;
  if found then
    raise exception 'Nomor HP itu sudah dipakai pelanggan "%" (%). Kemungkinan perusahaannya sama dengan nama berbeda — pilih dari daftar pencarian.',
      v_ada.nama, coalesce('dipegang sales ' || v_ada.sales, 'belum bertuan');
  end if;

  insert into public.customers (nama, hp, lokasi, sales_rep_id)
  values (v_nama, v_hp, v_lok, v_rep)
  returning id into v_id;   -- trigger customers_rapi_nama merapikan nama (PT di depan), jejak mengisi dibuat_oleh
  return v_id;
end $$;
revoke all on function public.buat_pelanggan_baru(text, text, text, bigint) from public, anon;
grant execute on function public.buat_pelanggan_baru(text, text, text, bigint) to authenticated;

-- ── (5) #48 penawaran selalu atas nama pemegang pelanggan ────────────────
create or replace function public.quotes_jaga_sales()
returns trigger
language plpgsql security definer set search_path = public as $function$
declare
  v_peran   text   := public.peran_saya();
  v_saya    bigint;
  v_pemilik bigint;
  v_nama    text;
begin
  if tg_op = 'INSERT' then
    new.dibuat_oleh := coalesce(auth.uid(), new.dibuat_oleh);
    new.dibuat_pada := now();
  end if;
  select c.sales_rep_id into v_pemilik from public.customers c where c.id = new.customer_id;

  if v_peran = 'sales' then
    v_saya := public.sales_rep_saya();
    if v_saya is null then
      raise exception 'Akun Anda belum ditautkan ke nama sales, jadi penawaran ini tidak punya pemilik dan Anda sendiri tidak akan bisa membukanya lagi. Minta owner membuka tab Pengguna lalu mengisi "Masuk sebagai" untuk akun ini.';
    end if;
    if tg_op = 'INSERT' and new.sales_rep_id is null then new.sales_rep_id := v_saya; end if;
    if new.sales_rep_id is distinct from v_saya then
      select nama into v_nama from public.sales_reps where id = new.sales_rep_id;
      raise exception 'Penawaran ini akan tercatat atas nama % — bukan Anda. Sales hanya bisa membuat penawaran untuk dirinya sendiri.',
        coalesce(v_nama, 'sales lain');
    end if;
  elsif tg_op = 'INSERT' and new.sales_rep_id is null then
    new.sales_rep_id := v_pemilik;   -- tanpa pilihan: ikut pemilik pelanggan
  end if;

  if v_peran <> 'sales' and new.sales_rep_id is null then
    raise exception 'Pilih dulu sales yang diwakili — penawaran tanpa sales tidak akan terlihat oleh sales mana pun.';
  end if;

  -- #48 (berkas 109): SEMUA peran — pelanggan bertuan hanya untuk sales pemegangnya.
  if v_pemilik is not null and new.sales_rep_id is distinct from v_pemilik then
    select nama into v_nama from public.sales_reps where id = v_pemilik;
    raise exception 'Pelanggan ini sudah dipegang sales %. Penawaran untuknya hanya bisa atas nama % — bila memang perlu, pindahkan dulu pelanggannya di tab Pelanggan (owner/GM/staff).',
      coalesce(v_nama, 'lain'), coalesce(v_nama, 'sales itu');
  end if;
  return new;
end $function$;

-- ── (6) #40 pencatat spesifikasi terakhir ────────────────────────────────
create or replace function public.catat_spesifikasi_sales(p_quote bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare v_rep bigint;
begin
  if not public.boleh_tulis_quote(p_quote) then
    raise exception 'Anda tidak berhak mengubah penawaran ini.' using errcode = '42501';
  end if;
  select sales_rep_id into v_rep from public.quotes where id = p_quote;
  if v_rep is null then return; end if;
  -- baris berspesifikasi → simpan/perbarui; baris produk yang spesifikasinya dikosongkan → lupakan
  insert into public.spesifikasi_sales (product_id, sales_rep_id, spesifikasi, quote_id, diubah_pada, diubah_oleh)
  select distinct on (l.product_id) l.product_id, v_rep, btrim(l.spesifikasi), p_quote, now(), auth.uid()
    from public.quote_lines l
   where l.quote_id = p_quote and l.product_id is not null and btrim(coalesce(l.spesifikasi, '')) <> ''
   order by l.product_id, l.urut desc
  on conflict (product_id, sales_rep_id) do update
     set spesifikasi = excluded.spesifikasi, quote_id = excluded.quote_id,
         diubah_pada = excluded.diubah_pada, diubah_oleh = excluded.diubah_oleh;
  delete from public.spesifikasi_sales s
   where s.sales_rep_id = v_rep
     and s.product_id in (select l.product_id from public.quote_lines l
                           where l.quote_id = p_quote and l.product_id is not null
                           group by l.product_id
                          having bool_and(btrim(coalesce(l.spesifikasi, '')) = ''));
end $$;
revoke all on function public.catat_spesifikasi_sales(bigint) from public, anon;
grant execute on function public.catat_spesifikasi_sales(bigint) to authenticated;

-- ── (7) simpan_penawaran: pelanggan baru, kepada dari master, mode PPN, spesifikasi ──
create or replace function public.simpan_penawaran(p_kepala jsonb, p_baris jsonb)
returns jsonb
language plpgsql set search_path = public as $function$
declare
  v_id      bigint;
  v_nomor   text;
  v_tgl     date;
  v_hari    text := nullif(btrim(coalesce(p_kepala->>'berlaku_hari', '')), '');
  v_mode    text := coalesce(nullif(btrim(p_kepala->>'mode_ppn'), ''), 'exclude');
  v_cust    bigint := nullif(p_kepala->>'customer_id', '')::bigint;
  v_rep     bigint := nullif(p_kepala->>'sales_rep_id', '')::bigint;
  v_baru    jsonb := p_kepala->'pelanggan_baru';
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
  -- #41: pelanggan baru dibuat di sini, satu transaksi dengan penawarannya
  if v_cust is null and jsonb_typeof(v_baru) = 'object' then
    v_cust := public.buat_pelanggan_baru(v_baru->>'nama', v_baru->>'hp', v_baru->>'lokasi',
                                         case when public.peran_saya() = 'sales' then null else v_rep end);
  end if;
  if v_cust is null then
    raise exception 'Pilih perusahaannya dulu — dari daftar pencarian, atau isi sebagai pelanggan baru.';
  end if;
  select c.nama into v_kepada from public.customers c where c.id = v_cust;   -- #47: nama master (sudah rapi)
  v_tgl := coalesce(nullif(p_kepala->>'tanggal', '')::date, current_date);
  for coba in 1..10 loop
    v_nomor := public.nomor_penawaran_baru(v_tgl);   -- di luar sub-blok: kenaikan counter bertahan
    begin
      insert into public.quotes (customer_id, nomor, tanggal, berlaku_hari, kepada, catatan, sales_rep_id, mode_ppn)
      values (v_cust, v_nomor, v_tgl,
              v_hari::int,                                                  -- #5: kosong = tanpa batas
              coalesce(v_kepada, nullif(btrim(p_kepala->>'kepada'), '')),
              nullif(btrim(p_kepala->>'catatan'), ''),
              v_rep, v_mode)
      returning id into v_id;
      exit;
    exception when unique_violation then
      get stacked diagnostics v_kendala = constraint_name;
      if v_kendala is distinct from 'quotes_nomor_uniq' then raise; end if;
      v_id := null;                                                     -- nomor bentrok → ambil berikutnya
    end;
  end loop;
  if v_id is null then
    raise exception 'Nomor penawaran bentrok terus (10 kali). Coba simpan sekali lagi; bila tetap gagal, hubungi owner.';
  end if;
  for b in select value from jsonb_array_elements(p_baris) loop
    n := n + 1;
    if nullif(b->>'product_id', '') is null and nullif(b->>'set_id', '') is null
       and coalesce(jsonb_typeof(b->'set_komponen'), '') <> 'array' then   -- #28: set inline
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
                                      qty, satuan, harga, harga_list, urut)
      values (v_id, nullif(b->>'product_id', '')::bigint, nullif(b->>'set_id', '')::bigint,
              case when jsonb_typeof(b->'set_komponen') = 'array' then b->'set_komponen' end,
              coalesce(nullif(btrim(b->>'deskripsi'), ''), '—'), nullif(btrim(b->>'spesifikasi'), ''),
              (b->>'qty')::numeric, coalesce(nullif(b->>'satuan', ''), 'pcs'),
              (b->>'harga')::numeric, nullif(b->>'harga_list', '')::numeric, n);   -- tanpa pembulatan (#12)
    exception when check_violation then
      raise exception 'Baris %: set tidak boleh sekaligus menunjuk produk/set master, dan jumlah set harus bulat.', n;
    end;
  end loop;
  perform public.catat_spesifikasi_sales(v_id);   -- #40
  return jsonb_build_object('id', v_id, 'nomor', v_nomor, 'customer_id', v_cust, 'kepada', v_kepada);
end $function$;
