-- Berkas 87 (#11 #4 #3 #1): penawaran per sales.
--
-- Masalah (terverifikasi di DEV):
--   • Sales TIDAK bisa menyimpan penawaran. FE: POST /quotes (return=representation) tanpa lead_id.
--     RLS quote_baca untuk sales hanya meloloskan quote yang lead_id → leads.sales_rep_id =
--     sales_rep_saya(), jadi INSERT…RETURNING ditolak "new row violates row-level security policy
--     for table quotes". quote_lines (ql_baca/ql_tulis) juga butuh tautan lead. Tiap kegagalan
--     membuang satu nomor penawaran (nomor_penawaran_baru dipanggil terpisah lebih dulu).
--   • quote_ubah: USING NULL (= false) → UPDATE quotes tertutup untuk semua orang.
--   • quotes.dibuat_oleh tidak pernah terisi (tanpa default/trigger, FE tidak mengirim).
--   • #11 "Vonny membuat penawaran mewakili sales" belum ada: quotes tidak punya kolom sales.
--   • #1 baris set di penawaran tidak punya tempat (quote_lines tanpa set_id) → FE membuangnya.
--   • #4 RLS customers menyembunyikan pelanggan sales lain → sales mengira pelanggannya belum ada
--     dan membuat nama baru (dobel).
--
-- Perubahan (aditif & kompatibel mundur — index.html lama tetap jalan, bahkan sales jadi bisa
-- menyimpan karena trigger (3) yang mengisi sales_rep_id):
-- (1) kolom quotes.sales_rep_id (FK sales_reps) + indeks; quote_lines.set_id (FK product_sets,
--     ON DELETE SET NULL — hapus set tidak diblokir; deskripsi/spesifikasi baris = jejak);
--     tiga CHECK NOT VALID di quote_lines (qty > 0, harga >= 0, bukan produk DAN set sekaligus).
-- (2) backfill sales_rep_id dari lead (lalu dari pembuat ber-peran sales). DEV: 0 baris (no-op).
--     Pulihkan: update quotes set sales_rep_id = null (kolom baru, tidak ada nilai lama yang hilang).
-- (3) trigger quotes_jaga_sales (BEFORE INSERT / UPDATE OF sales_rep_id, customer_id):
--       · INSERT: dibuat_oleh = auth.uid(), dibuat_pada = now()
--       · sales  : sales_rep_id otomatis = dirinya; mengisi sales lain ditolak; akun belum ditautkan
--                  ke nama sales ditolak (penawarannya akan yatim)
--       · vonny/owner/gm/staff tanpa pilihan: ikut sales pemilik pelanggan
--       · vonny wajib punya sales yang diwakili
--       · sales & vonny: pelanggan bertuan hanya untuk sales pemiliknya; owner/gm/staff boleh beda
--         (konsisten dengan form PO). Tidak ada klaim pelanggan otomatis di sini (klaim tetap saat PO).
-- (4) helper RLS quote_lines: boleh_lihat_quote(), boleh_tulis_quote() (SECURITY DEFINER).
-- (5) policy quotes & quote_lines berbasis quotes.sales_rep_id (lead lama tetap didukung); nama policy
--     tetap (ALTER, bukan DROP); peran dibatasi ke authenticated. quote_ubah dibuka untuk
--     owner/gm/staff/vonny (koreksi sales penawaran), sales tetap tidak bisa mengubah kepala.
-- (6) RPC cek_pemilik_pelanggan(p_nama, p_rep) (#4): HANYA nama pelanggan + nama sales pemiliknya,
--     minimal 3 huruf, maksimal 5 hasil, tanpa id/HP/alamat. Peran di luar boleh_baca() → kosong.
-- (7) RPC simpan_penawaran(p_kepala, p_baris): SECURITY INVOKER (RLS + trigger tetap berlaku),
--     nomor + kepala + baris dalam satu transaksi → gagal = nomor tidak terbuang. Tanpa pembulatan
--     (#12). Baris boleh produk ATAU set (#1). Masa berlaku kosong = tanpa batas (#5).
-- Galat aturan bisnis sengaja errcode P0001 (HTTP 400), bukan 42501 (403): FE mengeluarkan sesi
-- sesudah 3 kali 403 beruntun (BATAS_TOLAK), dan salah pilih pelanggan bukan alasan untuk itu.
--
-- Uji (transaksi rollback, DEV): sales simpan (RETURNING) untuk pelanggan sendiri LOLOS; pelanggan
-- sales lain DITOLAK; vonny mewakili sales X → tercatat X, X bisa lihat, sales Y tidak; baris set
-- tersimpan; counter tidak naik saat gagal.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026 (migrasi berkas87_penawaran_per_sales).
-- Belum ke produksi. Urutan di produksi: berkas ini DULU, baru index.html baru (FE baru memanggil
-- kolom/RPC di sini).

-- 1) kolom
alter table public.quotes add column if not exists sales_rep_id bigint references public.sales_reps(id);
create index if not exists quotes_sales_rep_idx on public.quotes(sales_rep_id);
alter table public.quote_lines add column if not exists set_id bigint
  references public.product_sets(id) on delete set null;
create index if not exists quote_lines_set_idx on public.quote_lines(set_id);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_qty_positif') then
    alter table public.quote_lines add constraint quote_lines_qty_positif check (qty > 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_harga_wajar') then
    alter table public.quote_lines add constraint quote_lines_harga_wajar check (harga >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'quote_lines_produk_atau_set') then
    alter table public.quote_lines add constraint quote_lines_produk_atau_set
      check (product_id is null or set_id is null) not valid;
  end if;
end $$;

-- 2) backfill — SEBELUM trigger (3) dibuat, supaya tidak terkena penjaganya.
update public.quotes q set sales_rep_id = l.sales_rep_id
  from public.leads l
 where l.id = q.lead_id and q.sales_rep_id is null and l.sales_rep_id is not null;
update public.quotes q set sales_rep_id = sr.id
  from public.sales_reps sr join public.profiles p on p.id = sr.profile_id
 where sr.profile_id = q.dibuat_oleh and p.peran = 'sales' and q.sales_rep_id is null;

-- 3) trigger penjaga pemilik penawaran
create or replace function public.quotes_jaga_sales()
returns trigger language plpgsql security definer set search_path = public as $$
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
    new.sales_rep_id := v_pemilik;   -- vonny/owner/gm/staff tanpa pilihan: ikut pemilik pelanggan
  end if;

  if v_peran = 'vonny' and new.sales_rep_id is null then
    raise exception 'Pilih dulu sales yang diwakili — penawaran tanpa sales tidak akan terlihat oleh sales mana pun.';
  end if;

  -- sales & vonny: pelanggan bertuan hanya untuk sales pemiliknya. owner/gm/staff boleh beda (seperti PO).
  if v_peran in ('sales','vonny') and v_pemilik is not null
     and new.sales_rep_id is distinct from v_pemilik then
    select nama into v_nama from public.sales_reps where id = v_pemilik;
    raise exception 'Pelanggan ini sudah dipegang sales %. Penawaran untuknya hanya bisa atas nama % — minta owner/GM/staff memindahkan pelanggannya bila memang perlu.',
      coalesce(v_nama, 'lain'), coalesce(v_nama, 'sales itu');
  end if;
  return new;
end $$;
drop trigger if exists quotes_jaga_sales on public.quotes;
create trigger quotes_jaga_sales before insert or update of sales_rep_id, customer_id
  on public.quotes for each row execute function public.quotes_jaga_sales();
revoke execute on function public.quotes_jaga_sales() from public, anon;

-- 4) helper RLS quote_lines
create or replace function public.boleh_lihat_quote(p_quote bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.peran_saya() = 'vonny' or public.boleh_lihat_semua_lead()
      or exists (select 1 from public.quotes q left join public.leads l on l.id = q.lead_id
                  where q.id = p_quote and public.sales_rep_saya() is not null
                    and (q.sales_rep_id = public.sales_rep_saya()
                         or (q.sales_rep_id is null and l.sales_rep_id = public.sales_rep_saya())))
$$;
create or replace function public.boleh_tulis_quote(p_quote bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.peran_saya() in ('owner','gm','staff','vonny')
      or (public.peran_saya() = 'sales' and exists (select 1 from public.quotes q
            where q.id = p_quote and q.sales_rep_id = public.sales_rep_saya()))
$$;
revoke execute on function public.boleh_lihat_quote(bigint), public.boleh_tulis_quote(bigint) from public, anon;
grant  execute on function public.boleh_lihat_quote(bigint), public.boleh_tulis_quote(bigint) to authenticated;

-- 5) policy (nama tetap; ALTER, bukan DROP)
alter policy quote_baca on public.quotes to authenticated using (
  public.peran_saya() = 'vonny' or public.boleh_lihat_semua_lead()
  or (public.sales_rep_saya() is not null and (
        sales_rep_id = public.sales_rep_saya()
        or (sales_rep_id is null and exists (select 1 from public.leads l
              where l.id = quotes.lead_id and l.sales_rep_id = public.sales_rep_saya())))));
alter policy quote_tambah on public.quotes to authenticated with check (
  (public.boleh_ubah_crm() or public.peran_saya() = 'vonny')
  and public.pelanggan_saya(customer_id)
  and (public.peran_saya() <> 'sales' or sales_rep_id = public.sales_rep_saya()));
alter policy quote_ubah on public.quotes to authenticated
  using      (public.peran_saya() in ('owner','gm','staff','vonny'))
  with check (public.peran_saya() in ('owner','gm','staff','vonny'));
alter policy ql_baca  on public.quote_lines to authenticated using (public.boleh_lihat_quote(quote_id));
alter policy ql_tulis on public.quote_lines to authenticated
  using (public.boleh_tulis_quote(quote_id)) with check (public.boleh_tulis_quote(quote_id));

-- 6) RPC #4: siapa pemegang pelanggan bernama mirip (nama + nama sales saja)
create or replace function public.cek_pemilik_pelanggan(p_nama text, p_rep bigint default null)
returns table(nama text, sales_nama text)
language plpgsql stable security definer set search_path = public as $$
declare t text := btrim(coalesce(p_nama, '')); v_acuan bigint;
begin
  if not public.boleh_baca() then return; end if;      -- peran lain: kosong, tanpa bocoran
  if char_length(t) < 3 then return; end if;
  -- sales: acuannya selalu dirinya sendiri (p_rep diabaikan); peran lain: sales yang sedang dipilih.
  v_acuan := case when public.peran_saya() = 'sales' then public.sales_rep_saya() else p_rep end;
  t := replace(replace(replace(t, '\', '\\'), '%', '\%'), '_', '\_');
  return query
    select c.nama, sr.nama || case when sr.aktif then '' else ' (nonaktif)' end
      from public.customers c join public.sales_reps sr on sr.id = c.sales_rep_id
     where c.nama ilike '%' || t || '%'
       and (v_acuan is null or c.sales_rep_id <> v_acuan)
     order by c.nama limit 5;
end $$;
revoke execute on function public.cek_pemilik_pelanggan(text, bigint) from public, anon;
grant  execute on function public.cek_pemilik_pelanggan(text, bigint) to authenticated;

-- 7) RPC simpan atomik (SECURITY INVOKER → RLS + trigger tetap berlaku; gagal = counter ikut rollback)
create or replace function public.simpan_penawaran(p_kepala jsonb, p_baris jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_id    bigint;
  v_nomor text;
  v_tgl   date;
  v_hari  text := nullif(btrim(coalesce(p_kepala->>'berlaku_hari', '')), '');
  n       int  := 0;
  b       jsonb;
begin
  if not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Anda tidak berhak membuat penawaran.' using errcode = '42501';
  end if;
  if nullif(p_kepala->>'customer_id', '') is null then
    raise exception 'Pilih perusahaannya dulu.';
  end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' or jsonb_array_length(p_baris) = 0 then
    raise exception 'Penawaran tanpa baris tidak disimpan.';
  end if;
  if v_hari is not null and v_hari !~ '^[0-9]{1,4}$' then
    raise exception 'Masa berlaku harus jumlah hari (bilangan bulat), atau kosong = tanpa batas.';
  end if;
  v_tgl   := coalesce(nullif(p_kepala->>'tanggal', '')::date, current_date);
  v_nomor := public.nomor_penawaran_baru(v_tgl);
  insert into public.quotes (customer_id, nomor, tanggal, berlaku_hari, kepada, catatan, sales_rep_id)
  values ((p_kepala->>'customer_id')::bigint, v_nomor, v_tgl,
          v_hari::int,                                                  -- #5: kosong = tanpa batas
          nullif(btrim(p_kepala->>'kepada'), ''), nullif(btrim(p_kepala->>'catatan'), ''),
          nullif(p_kepala->>'sales_rep_id', '')::bigint)
  returning id into v_id;
  for b in select value from jsonb_array_elements(p_baris) loop
    n := n + 1;
    if nullif(b->>'product_id', '') is null and nullif(b->>'set_id', '') is null then
      raise exception 'Baris % belum memilih barang atau set.', n;
    end if;
    if nullif(b->>'qty', '') is null or (b->>'qty')::numeric <= 0 then
      raise exception 'Baris %: qty harus lebih dari 0.', n;
    end if;
    if nullif(b->>'harga', '') is null or (b->>'harga')::numeric < 0 then
      raise exception 'Baris %: harga belum diisi.', n;
    end if;
    insert into public.quote_lines (quote_id, product_id, set_id, deskripsi, spesifikasi,
                                    qty, satuan, harga, harga_list, urut)
    values (v_id, nullif(b->>'product_id', '')::bigint, nullif(b->>'set_id', '')::bigint,
            coalesce(nullif(btrim(b->>'deskripsi'), ''), '—'), nullif(btrim(b->>'spesifikasi'), ''),
            (b->>'qty')::numeric, coalesce(nullif(b->>'satuan', ''), 'pcs'),
            (b->>'harga')::numeric, nullif(b->>'harga_list', '')::numeric, n);   -- tanpa pembulatan (#12)
  end loop;
  return jsonb_build_object('id', v_id, 'nomor', v_nomor);
end $$;
revoke execute on function public.simpan_penawaran(jsonb, jsonb) from public, anon;
grant  execute on function public.simpan_penawaran(jsonb, jsonb) to authenticated;
