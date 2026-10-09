-- ═══════════════════════════════════════════════════════════════════════
-- 137 · Temuan keamanan #4 (keputusan Hannes 9 Okt, no. 12–13): penawaran yang sudah tersimpan dikunci
--
-- Celah (uji DEV, rollback): quote_lines tidak punya penjaga baris dan grant authenticated penuh; RLS ql_tulis FOR ALL
-- (berkas 87). Lewat REST: baris teks bebas disisipkan (melompati usulan item #59), produk baris diubah jadi teks bebas,
-- harga/qty/harga_list baris penawaran yang sudah terbit diubah, semua baris dihapus (penawaran kosong), baris
-- ditambahkan ke penawaran lama. Kepala penawaran (tanggal, mode PPN, kepada, TOP, pelanggan, cap waktu) bisa di-PATCH
-- owner/GM/staff/Vonny (policy quote_ubah) — dan karena cap waktu bisa di-PATCH, penjaga "dibuat di transaksi yang
-- sama" saja bisa dipalsukan. Kepala tanpa baris bisa di-POST.
-- Layar tidak pernah menulis quotes/quote_lines langsung: hanya POST /rpc/simpan_penawaran (SECURITY INVOKER); revisi =
-- "Buat penawaran baru dari ini" (#44).
--
-- Perbaikan (berlaku untuk SEMUA peran bersesi, termasuk owner/GM/Vonny; migrasi/tanpa sesi apa adanya):
--  (1) quote_lines BEFORE INSERT (jaga_baris_quote): baris hanya boleh disisipkan dalam transaksi yang sama dengan
--      pembuatan kepalanya, oleh pembuatnya (quotes.dibuat_pada = now() dan dibuat_oleh = auth.uid(); keduanya diisi
--      quotes_jaga_sales saat INSERT). Baris wajib menunjuk barang master, set, atau set yang dirakit di baris itu —
--      teks bebas ditolak (barang baru lewat usulan #59). Pesan P0001 (bukan 23514/42501: handler check_violation di
--      simpan_penawaran dan BATAS_TOLAK di layar tidak terpicu).
--  (2) Hak UPDATE/DELETE/TRUNCATE quote_lines dan quotes dicabut dari public, anon, authenticated → baris & kepala
--      penawaran tersimpan tidak bisa diubah/dihapus lewat REST/GraphQL; cap waktu kepala tidak bisa dipalsukan.
--      Jalur sah yang tetap jalan (berjalan sebagai pemilik tabel): gabung_produk_usulan (SECURITY DEFINER), FK
--      product_sets ON DELETE SET NULL, quotes ON DELETE CASCADE. Policy quote_ubah/ql_tulis tidak dibuang (tidak
--      berpengaruh lagi untuk UPDATE/DELETE).
--  (3) quotes AFTER INSERT DEFERRABLE INITIALLY DEFERRED (quotes_wajib_baris): penawaran tanpa baris ditolak saat
--      commit — simpan_penawaran (kepala + baris satu transaksi) lolos.
--  (4) Tiga CHECK NOT VALID berkas 87 divalidasi bila data lama bersih (bila tidak: NOTICE, penjaga lain tetap naik).
-- Sisa (dicatat): bila pg_graphql aktif, satu request GraphQL bisa membuat kepala + baris sah sekaligus (melompati
-- simpan_penawaran, tetapi tetap kena bentuk baris, CHECK, RLS) — cek pra-rilis PROD di HANDOFF. harga_list baris tetap
-- kiriman klien (hanya tanda "di bawah list" di arsip penawaran; tidak ada gerbang yang memakainya).
-- Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- (1)
create or replace function public.jaga_baris_quote()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- migrasi / service role
  if not exists (select 1 from public.quotes q
                  where q.id = new.quote_id and q.dibuat_pada = now() and q.dibuat_oleh = auth.uid()) then
    raise exception 'Baris penawaran hanya dibuat bersama penawarannya (tombol Simpan penawaran). Penawaran yang sudah '
                    'tersimpan tidak bisa ditambah barisnya — buat penawaran baru dari penawaran itu bila perlu diubah.';
  end if;
  if new.product_id is null and new.set_id is null and new.set_komponen is null then
    raise exception 'Baris penawaran harus menunjuk barang di master, set, atau set yang dirakit di baris itu. Barang '
                    'yang belum ada di master dipakai lewat "+ item baru" (usulan) — baris teks bebas tidak disimpan.';
  end if;
  return new;
end $$;
comment on function public.jaga_baris_quote() is
  '137 (temuan #4): baris penawaran hanya lewat simpan_penawaran (transaksi & pembuat yang sama dengan kepala) dan wajib menunjuk produk/set/set inline.';
revoke all on function public.jaga_baris_quote() from public, anon, authenticated;
-- urutan abjad: quote_lines_jaga_baris menyala sebelum quote_lines_set_inline
create or replace trigger quote_lines_jaga_baris
  before insert on public.quote_lines
  for each row execute function public.jaga_baris_quote();

-- (2)
revoke update, delete, truncate on public.quote_lines from public, anon, authenticated;
revoke update, delete, truncate on public.quotes from public, anon, authenticated;

-- (3)
create or replace function public.quotes_wajib_baris()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return null; end if;   -- migrasi / service role
  if exists (select 1 from public.quotes q where q.id = new.id)
     and not exists (select 1 from public.quote_lines l where l.quote_id = new.id) then
    raise exception 'Penawaran tanpa baris tidak disimpan — pakai tombol Simpan penawaran.';
  end if;
  return null;
end $$;
revoke all on function public.quotes_wajib_baris() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.quotes'::regclass and tgname = 'quotes_wajib_baris') then
    create constraint trigger quotes_wajib_baris
      after insert on public.quotes deferrable initially deferred
      for each row execute function public.quotes_wajib_baris();
  end if;
end $$;

-- (4)
do $$
declare n int;
begin
  select count(*) into n from public.quote_lines
   where not (qty > 0) or not (harga >= 0) or not (product_id is null or set_id is null);
  if n = 0 then
    alter table public.quote_lines validate constraint quote_lines_qty_positif;
    alter table public.quote_lines validate constraint quote_lines_harga_wajar;
    alter table public.quote_lines validate constraint quote_lines_produk_atau_set;
  else
    raise notice '137: % baris penawaran lama melanggar CHECK qty/harga/produk-atau-set — VALIDATE ditunda (laporkan ke Hannes).', n;
  end if;
end $$;

do $$ begin
  if has_table_privilege('authenticated', 'public.quote_lines', 'update')
     or has_table_privilege('authenticated', 'public.quotes', 'update')
     or not has_table_privilege('authenticated', 'public.quote_lines', 'insert')
     or not has_table_privilege('authenticated', 'public.quotes', 'insert') then
    raise exception '137: hak quotes/quote_lines tidak sesuai';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.quote_lines'::regclass and tgname = 'quote_lines_jaga_baris')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.quotes'::regclass and tgname = 'quotes_wajib_baris') then
    raise exception '137: trigger penawaran belum terpasang';
  end if;
end $$;
