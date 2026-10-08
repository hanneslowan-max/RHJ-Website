-- ═══════════════════════════════════════════════════════════════════════
-- 132 · #58 Grup pelanggan (usulan 7 Okt, keputusan Hannes 8 Okt: PO dikirim oleh masing-masing divisi)
--
-- Masalahnya: penawaran ditujukan ke satu pelanggan, padahal satu grup (mis. Garuda Metalindo) punya beberapa PT /
-- divisi yang dipegang sales berbeda. Yang dibuat:
--   (1) customer_groups — grup pelanggan (nama, nama induk untuk dokumen, catatan). Dibuat & diubah owner/GM saja
--       (RPC simpan_grup_pelanggan); tanpa hapus (grup dikosongkan saja).
--   (2) customers.grup_id — anggota grup. Pemegang (sales_rep_id) TIDAK berubah. Hanya owner/GM yang mengatur
--       (RPC atur_anggota_grup; trigger customers_jaga_grup menolak jalur lain, mis. PATCH sales).
--   (3) Penawaran boleh DITUJUKAN ke grup: dokumen bertuliskan "<induk> — Divisi <pelanggan>" (mis. "PT Garuda
--       Metalindo — Divisi Indo Kida Plating"), tetapi penawarannya tetap tercatat milik pelanggan divisi itu
--       (customer_id, sales, komisi, harga khusus, piutang tidak berubah). quotes.kepada_grup = judul yang tercetak,
--       DIHITUNG database (trigger quotes_judul_grup dari grup pelanggannya — isian bebas dari layar/REST tidak
--       dipakai) dan dibekukan saat penawaran disimpan. simpan_penawaran menerima p_kepala.ke_grup.
--   (4) daftar_grup_pelanggan(): semua peran baca (boleh_baca) melihat grup, anggotanya, dan sales pemegangnya —
--       TANPA harga/transaksi (sama dengan #49); owner/GM juga melihat per anggota: penjualan (Σ grand total SP tidak
--       batal), penjualan tahun ini, piutang (SP ber-invoice belum lunas — sama dengan laporan_piutang), jumlah SP.
--   PO tetap dikirim tiap divisi (keputusan Hannes 8 Okt) → tidak ada perubahan PO/SP/komisi.
--
-- Review adversarial (DEV: migrasi 132b): judul_grup_pelanggan hanya menjawab peran baca (boleh_baca) — dulu akun
-- pending/nonaktif bisa membaca nama anggota grup lewat RPC. FE: data grup ditarik segar saat pelanggan dipilih di
-- penawaran / laci pelanggan dibuka / muat ulang diam; pencarian penawaran ikut judul grup.
--
-- Tidak ada DROP. Tidak ada data yang diubah.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) grup ────────────────────────────────────────────────────────────
create table if not exists public.customer_groups (
  id           bigserial primary key,
  nama         text not null,
  nama_dokumen text,
  catatan      text,
  dibuat_oleh  uuid default auth.uid(),
  dibuat_pada  timestamptz not null default now(),
  constraint customer_groups_nama_sah check (char_length(btrim(nama)) between 2 and 120),
  constraint customer_groups_dokumen_sah check (nama_dokumen is null or char_length(btrim(nama_dokumen)) between 2 and 160),
  constraint customer_groups_catatan_sah check (catatan is null or char_length(catatan) <= 1000)
);
comment on table public.customer_groups is
  'Grup pelanggan (#58, berkas 132): beberapa PT/divisi satu grup; pemegang tiap anggota tetap. Diubah lewat RPC owner/GM.';
create unique index if not exists customer_groups_nama_uniq on public.customer_groups (lower(btrim(nama)));
alter table public.customer_groups enable row level security;
do $$
begin
  if not exists (select 1 from pg_policy where polname = 'grup_baca' and polrelid = 'public.customer_groups'::regclass) then
    create policy grup_baca on public.customer_groups for select to authenticated using (public.boleh_baca());
  end if;
end $$;
revoke all on public.customer_groups from anon;
grant select on public.customer_groups to authenticated;

-- ── (2) anggota ─────────────────────────────────────────────────────────
alter table public.customers add column if not exists grup_id bigint references public.customer_groups(id);
create index if not exists customers_grup_idx on public.customers (grup_id) where grup_id is not null;

create or replace function public.jaga_grup_pelanggan()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;   -- migrasi / owner / GM
  if (tg_op = 'INSERT' and new.grup_id is not null)
     or (tg_op = 'UPDATE' and new.grup_id is distinct from old.grup_id) then
    raise exception 'Grup pelanggan hanya diatur owner/GM (tab Pelanggan › Grup pelanggan).' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_grup_pelanggan() from public, anon, authenticated;
create or replace trigger customers_jaga_grup
  before insert or update of grup_id on public.customers
  for each row execute function public.jaga_grup_pelanggan();

-- ── (3) penawaran ditujukan ke grup ─────────────────────────────────────
alter table public.quotes add column if not exists kepada_grup text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'quotes_kepada_grup_sah' and conrelid = 'public.quotes'::regclass) then
    alter table public.quotes add constraint quotes_kepada_grup_sah
      check (kepada_grup is null or char_length(kepada_grup) between 2 and 300);
  end if;
end $$;

-- "<induk> — Divisi <pelanggan tanpa bentuk badan usaha di depan>"; null bila bukan anggota grup, atau pelanggan itu
-- sendiri induknya.
create or replace function public.judul_grup_pelanggan(p_customer bigint)
returns text language sql stable security definer set search_path = public as $$
  select case
    when g.id is null then null
    when public.kunci_nama_pelanggan(coalesce(nullif(btrim(g.nama_dokumen), ''), g.nama))
         = public.kunci_nama_pelanggan(c.nama) then null
    else coalesce(nullif(btrim(g.nama_dokumen), ''), btrim(g.nama)) || ' — Divisi '
         || btrim(regexp_replace(c.nama, '^(PT|CV|UD|PD|TB|Toko|Koperasi|Yayasan)\.?[[:space:]]+', '', 'i'))
  end
  from public.customers c
  left join public.customer_groups g on g.id = c.grup_id
  where c.id = p_customer
    and (auth.uid() is null or public.boleh_baca())   -- review: akun pending/nonaktif/peran tanpa baca tidak ikut melihat
$$;
revoke all on function public.judul_grup_pelanggan(bigint) from public, anon;
grant execute on function public.judul_grup_pelanggan(bigint) to authenticated;

create or replace function public.isi_judul_grup_penawaran()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- isian apa pun = "tujukan ke grup"; judulnya selalu dihitung dari grup pelanggan penawaran ini
  if new.kepada_grup is not null then
    new.kepada_grup := public.judul_grup_pelanggan(new.customer_id);
  end if;
  return new;
end $$;
revoke all on function public.isi_judul_grup_penawaran() from public, anon, authenticated;
create or replace trigger quotes_judul_grup
  before insert or update of kepada_grup, customer_id on public.quotes
  for each row execute function public.isi_judul_grup_penawaran();

-- simpan_penawaran (berkas 129) + p_kepala.ke_grup
create or replace function public.simpan_penawaran(p_kepala jsonb, p_baris jsonb)
returns jsonb language plpgsql set search_path = public as $$
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
  v_ke_grup boolean := lower(coalesce(p_kepala->>'ke_grup', '')) = 'true';        -- #58 (berkas 132)
  v_judul   text;
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
    if v_ke_grup then
      raise exception 'Pelanggan baru belum anggota grup pelanggan — penawarannya tidak bisa ditujukan ke grup.';
    end if;
    v_cust := public.buat_pelanggan_baru(v_baru->>'nama', v_baru->>'hp', v_baru->>'lokasi',
                                         case when public.peran_saya() = 'sales' then null else v_rep end);
  end if;
  if v_cust is null then
    raise exception 'Pilih perusahaannya dulu — dari daftar pencarian, atau isi sebagai pelanggan baru.';
  end if;
  if v_ke_grup then   -- #58: hanya anggota grup (dan bukan induknya sendiri)
    v_judul := public.judul_grup_pelanggan(v_cust);
    if v_judul is null then
      raise exception 'Pelanggan ini bukan anggota grup pelanggan (atau pelanggan induknya sendiri) — penawarannya tidak bisa ditujukan ke grup.';
    end if;
  end if;
  select c.nama into v_kepada from public.customers c where c.id = v_cust;
  v_tgl := coalesce(nullif(p_kepala->>'tanggal', '')::date, current_date);
  for coba in 1..10 loop
    v_nomor := public.nomor_penawaran_baru(v_tgl);
    begin
      insert into public.quotes (customer_id, nomor, tanggal, berlaku_hari, kepada, catatan, sales_rep_id, mode_ppn,
                                 up, email, top, kepada_grup)
      values (v_cust, v_nomor, v_tgl,
              v_hari::int,
              coalesce(v_kepada, nullif(btrim(p_kepala->>'kepada'), '')),
              nullif(btrim(p_kepala->>'catatan'), ''),
              v_rep, v_mode,
              v_up, v_email, v_top, v_judul)   -- trigger quotes_judul_grup menghitung ulang judulnya
      returning id, kepada_grup into v_id, v_judul;
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
  return jsonb_build_object('id', v_id, 'nomor', v_nomor, 'customer_id', v_cust, 'kepada', v_kepada,
                            'kepada_grup', v_judul);
end $$;

-- ── (4) daftar & pengaturan grup ────────────────────────────────────────
create or replace function public.daftar_grup_pelanggan()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_owner boolean := public.setara_owner(); v_saya bigint := public.sales_rep_saya();
begin
  if auth.uid() is null or not public.boleh_baca() then
    raise exception 'Anda tidak berwenang melihat grup pelanggan.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x.g order by lower(x.g->>'nama'))
      from (select jsonb_build_object(
                     'id', g.id, 'nama', g.nama, 'nama_dokumen', g.nama_dokumen, 'catatan', g.catatan,
                     'anggota', coalesce((
                        select jsonb_agg(
                                 jsonb_build_object('customer_id', c.id, 'nama', c.nama, 'cabang', c.cabang,
                                                    'sales_rep_id', c.sales_rep_id,
                                                    'sales_nama', sr.nama || case when sr.aktif then '' else ' (nonaktif)' end,
                                                    'milik_saya', v_saya is not null and c.sales_rep_id = v_saya)
                                 || case when v_owner then (
                                      select jsonb_build_object(
                                               'jumlah_sp', count(*) filter (where not s.batal),
                                               'penjualan', coalesce(sum(r.grand_total) filter (where not s.batal), 0),
                                               'penjualan_tahun_ini', coalesce(sum(r.grand_total) filter (
                                                    where not s.batal and s.tanggal >= date_trunc('year', current_date)::date), 0),
                                               'piutang', coalesce(sum(r.grand_total) filter (
                                                    where not s.batal and s.no_invoice is not null and s.tgl_invoice is not null
                                                      and not s.lunas), 0))
                                        from public.sales_orders s
                                        left join public.so_ringkas r on r.so_id = s.id
                                       where s.customer_id = c.id)
                                    else '{}'::jsonb end
                                 order by c.nama_urut, c.id)
                          from public.customers c
                          left join public.sales_reps sr on sr.id = c.sales_rep_id
                         where c.grup_id = g.id), '[]'::jsonb)) as g
              from public.customer_groups g) x), '[]'::jsonb);
end $$;
revoke all on function public.daftar_grup_pelanggan() from public, anon;
grant execute on function public.daftar_grup_pelanggan() to authenticated;

create or replace function public.simpan_grup_pelanggan(p_id bigint, p_nama text, p_nama_dokumen text, p_catatan text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_nama text := btrim(coalesce(p_nama, '')); v_dok text := nullif(btrim(coalesce(p_nama_dokumen, '')), '');
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh mengatur grup pelanggan.' using errcode = '42501';
  end if;
  if char_length(v_nama) < 2 or char_length(v_nama) > 120 then
    raise exception 'Nama grup wajib diisi (2–120 huruf).';
  end if;
  if v_dok is not null and (char_length(v_dok) < 2 or char_length(v_dok) > 160) then
    raise exception 'Nama induk di dokumen 2–160 huruf, atau kosongkan (memakai nama grup).';
  end if;
  begin
    if p_id is null then
      insert into public.customer_groups (nama, nama_dokumen, catatan)
      values (v_nama, v_dok, nullif(btrim(coalesce(p_catatan, '')), ''))
      returning id into v_id;
    else
      update public.customer_groups
         set nama = v_nama, nama_dokumen = v_dok, catatan = nullif(btrim(coalesce(p_catatan, '')), '')
       where id = p_id
      returning id into v_id;
      if v_id is null then raise exception 'Grup #% tidak ditemukan.', p_id using errcode = 'P0002'; end if;
    end if;
  exception when unique_violation then
    raise exception 'Grup bernama "%" sudah ada.', v_nama using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.simpan_grup_pelanggan(bigint, text, text, text) from public, anon;
grant execute on function public.simpan_grup_pelanggan(bigint, text, text, text) to authenticated;

-- p_grup null = keluarkan dari grupnya. Pindah dari grup lain ditolak (keluarkan dulu) supaya tidak tak sengaja.
create or replace function public.atur_anggota_grup(p_customer bigint, p_grup bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v_lama bigint; v_nama text; v_grup_lama text;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh mengatur anggota grup pelanggan.' using errcode = '42501';
  end if;
  select c.grup_id, c.nama into v_lama, v_nama from public.customers c where c.id = p_customer for update;
  if v_nama is null then raise exception 'Pelanggan #% tidak ditemukan.', p_customer using errcode = 'P0002'; end if;
  if p_grup is not null then
    if not exists (select 1 from public.customer_groups g where g.id = p_grup) then
      raise exception 'Grup #% tidak ditemukan.', p_grup using errcode = 'P0002';
    end if;
    if v_lama is not null and v_lama <> p_grup then
      select g.nama into v_grup_lama from public.customer_groups g where g.id = v_lama;
      raise exception '% sudah anggota grup "%" — keluarkan dulu dari grup itu.', v_nama, v_grup_lama using errcode = '23505';
    end if;
  end if;
  update public.customers set grup_id = p_grup where id = p_customer and grup_id is distinct from p_grup;
end $$;
revoke all on function public.atur_anggota_grup(bigint, bigint) from public, anon;
grant execute on function public.atur_anggota_grup(bigint, bigint) to authenticated;
