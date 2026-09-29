-- Berkas 93 (#11, temuan review berkas 87): nomor penawaran tidak bisa macet + sales nonaktif
-- tidak bisa membaca penawaran.
--
-- Masalah (terverifikasi di DEV dengan transaksi rollback, 28 Sep 2026):
--   (A) Nomor penawaran bisa macet permanen untuk SEMUA pengguna. simpan_penawaran (berkas 87)
--       mengambil nomor dan INSERT dalam satu transaksi. Bila nomor berikutnya sudah dipakai baris
--       lain (unique quotes_nomor_uniq), INSERT gagal 23505 dan kenaikan counter ikut ter-rollback →
--       percobaan berikutnya mendapat nomor yang SAMA lagi. Pemicunya terbuka: sales boleh
--       INSERT /quotes langsung dengan nomor bebas (quote_tambah tidak membatasi nomor), dan
--       owner/gm/staff/vonny boleh UPDATE nomor (quote_ubah). Uji: Alfred (sales) INSERT langsung
--       '022/PQ/MCE/IX/2026' → LOLOS; Iwan simpan_penawaran 2x → 2x 23505; counter tetap 21.
--       Bonus laten: lpad(n, 3) memotong nomor ≥ 1000 ('1000' → '100') → macet juga sesudah
--       penawaran ke-999 dalam sebulan.
--   (B) Cabang "milik sales" di quote_baca dan boleh_lihat_quote hanya memeriksa
--       sales_rep_saya() is not null, TANPA peran_saya() = 'sales' (po_baca, so_baca, lead_baca, dll.
--       memeriksanya). Akun sales yang dinonaktifkan / dikembalikan ke pending tetapi masih tertaut
--       di sales_reps.profile_id tetap membaca semua penawaran atas namanya (nomor, catatan, harga).
--       Uji: Alfred → nonaktif: quotes 1 baris + quote_lines '3.00 x 12345.67' terbaca, sedangkan
--       purchase_orders 0, leads 0.
--
-- Perubahan (aditif & kompatibel mundur — index.html lama tetap jalan: ia memanggil
-- nomor_penawaran_baru lalu POST /quotes dengan nomor itu, dan nomor itu lolos penjaga (3)):
-- (1) nomor_penawaran_format(n, tahun, bulan): satu-satunya tempat format nomor; ≥ 1000 tidak
--     dipotong.
-- (2) nomor_penawaran_baru: melompati nomor yang sudah dipakai baris quotes mana pun (SECURITY
--     DEFINER → melihat semua baris, tidak terhalang RLS). Nomor yang dilompati tetap "terpakai"
--     di counter bila transaksinya jadi.
-- (3) trigger quotes_jaga_nomor (BEFORE INSERT / UPDATE OF nomor):
--       · INSERT tanpa nomor → diisi dari counter (nomor_penawaran_baru).
--       · INSERT selain owner → nomor wajib nomor yang SUDAH dikeluarkan counter (format baku,
--         urutnya ≤ counter bulan itu). Nomor "masa depan" / format bebas ditolak.
--       · UPDATE nomor selain owner → ditolak (nomor dokumen diberikan sistem).
--       · auth.uid() null (migrasi / service role) tidak dijaga. Owner tetap boleh (impor data lama,
--         koreksi) — kalaupun owner memakai nomor masa depan, (2) dan (4) melompatinya.
-- (4) simpan_penawaran: INSERT kepala dalam sub-blok; bila bentrok quotes_nomor_uniq (mis. tulis
--     bersamaan), ambil nomor berikutnya dan ulangi (maks 10x). Kenaikan counter di luar sub-blok,
--     jadi tidak ikut ter-rollback → nomor terus maju.
-- (5) quote_baca & boleh_lihat_quote: cabang sales kini mensyaratkan peran_saya() = 'sales' (sama
--     seperti po_baca/lead_baca). Nonaktif/pending yang masih tertaut → 0 baris.
-- Galat aturan bisnis tetap errcode P0001 (HTTP 400), bukan 42501 (lihat catatan BATAS_TOLAK di 87).
--
-- Sengaja BELUM: mencabut INSERT/UPDATE langsung quotes/quote_lines untuk non-owner (host DEV masih
-- memakai index.html lama yang POST /quotes langsung). Setelah index.html baru terpasang di semua
-- host, pertimbangkan quote_tambah = hanya lewat simpan_penawaran.
-- Uji (transaksi rollback, DEV): lihat ringkasan di akhir berkas.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026 (migrasi berkas93_penawaran_nomor_tak_macet).
-- Belum ke produksi. Urutan di produksi: sesudah berkas 87.
-- Membalik (tidak ada data yang diubah berkas ini): jalankan ulang bagian 4, 5 (quote_baca) dan 7
-- dari berkas 87; nomor_penawaran_baru versi lama = versi di bawah TANPA loop dan dengan
-- lpad(n::text, 3, '0') langsung (berkas 66); lalu drop trigger quotes_jaga_nomor.

-- 1) format nomor (satu tempat)
create or replace function public.nomor_penawaran_format(p_urut integer, p_tahun integer, p_bulan integer)
returns text language sql immutable set search_path = public as $$
  select case when p_urut < 1000 then lpad(p_urut::text, 3, '0') else p_urut::text end
         || '/PQ/MCE/' || public.bulan_romawi(p_bulan) || '/' || p_tahun::text
$$;
revoke execute on function public.nomor_penawaran_format(integer, integer, integer) from public, anon;
grant  execute on function public.nomor_penawaran_format(integer, integer, integer) to authenticated;

-- 2) counter melompati nomor yang sudah terpakai
create or replace function public.nomor_penawaran_baru(p_tanggal date default current_date)
returns text language plpgsql security definer set search_path = public as $$
declare th integer := extract(year from p_tanggal)::int; bl integer := extract(month from p_tanggal)::int;
        n integer; v text;
begin
  if not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Anda tidak berhak mengambil nomor penawaran.' using errcode = '42501';
  end if;
  loop
    insert into public.quote_counter (tahun, bulan, urut) values (th, bl, 1)
    on conflict (tahun, bulan) do update set urut = public.quote_counter.urut + 1
    returning urut into n;
    v := public.nomor_penawaran_format(n, th, bl);
    exit when not exists (select 1 from public.quotes q where q.nomor = v);   -- sudah dipakai → lompati
  end loop;
  return v;
end $$;

-- 3) penjaga nomor untuk tulis langsung
create or replace function public.quotes_jaga_nomor()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_n text; v_th text; v_sah boolean := false;
begin
  if auth.uid() is null then return new; end if;                 -- migrasi / service role
  if tg_op = 'INSERT' then
    if nullif(btrim(coalesce(new.nomor, '')), '') is null then
      new.nomor := public.nomor_penawaran_baru(coalesce(new.tanggal, current_date));
      return new;
    end if;
    if public.peran_saya() = 'owner' then return new; end if;
    v_n  := split_part(new.nomor, '/', 1);
    v_th := split_part(new.nomor, '/', 5);
    if v_n ~ '^[0-9]{1,9}$' and v_th ~ '^[0-9]{4}$' then          -- cast hanya sesudah bentuknya pasti angka
      v_sah := exists (select 1 from public.quote_counter qc
                        where qc.tahun = v_th::int and qc.urut >= v_n::int
                          and public.nomor_penawaran_format(v_n::int, qc.tahun, qc.bulan) = new.nomor);
    end if;
    if not v_sah then
      raise exception 'Nomor penawaran % bukan nomor yang diberikan sistem. Kosongkan nomornya — database akan mengisinya.',
        new.nomor;
    end if;
    return new;
  end if;
  -- UPDATE OF nomor
  if new.nomor is distinct from old.nomor and public.peran_saya() <> 'owner' then
    raise exception 'Nomor penawaran % diberikan sistem dan tidak bisa diubah (hanya owner).', old.nomor;
  end if;
  return new;
end $$;
drop trigger if exists quotes_jaga_nomor on public.quotes;
create trigger quotes_jaga_nomor before insert or update of nomor
  on public.quotes for each row execute function public.quotes_jaga_nomor();
revoke execute on function public.quotes_jaga_nomor() from public, anon;

-- 4) simpan atomik yang tidak bisa macet
create or replace function public.simpan_penawaran(p_kepala jsonb, p_baris jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_id      bigint;
  v_nomor   text;
  v_tgl     date;
  v_hari    text := nullif(btrim(coalesce(p_kepala->>'berlaku_hari', '')), '');
  v_kendala text;
  n         int  := 0;
  b         jsonb;
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
  v_tgl := coalesce(nullif(p_kepala->>'tanggal', '')::date, current_date);
  for coba in 1..10 loop
    v_nomor := public.nomor_penawaran_baru(v_tgl);   -- di luar sub-blok: kenaikan counter bertahan
    begin
      insert into public.quotes (customer_id, nomor, tanggal, berlaku_hari, kepada, catatan, sales_rep_id)
      values ((p_kepala->>'customer_id')::bigint, v_nomor, v_tgl,
              v_hari::int,                                                  -- #5: kosong = tanpa batas
              nullif(btrim(p_kepala->>'kepada'), ''), nullif(btrim(p_kepala->>'catatan'), ''),
              nullif(p_kepala->>'sales_rep_id', '')::bigint)
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

-- 5) cabang sales hanya untuk peran sales aktif (nonaktif/pending yang masih tertaut → tertutup)
create or replace function public.boleh_lihat_quote(p_quote bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.peran_saya() = 'vonny' or public.boleh_lihat_semua_lead()
      or (public.peran_saya() = 'sales' and exists (
            select 1 from public.quotes q left join public.leads l on l.id = q.lead_id
             where q.id = p_quote and public.sales_rep_saya() is not null
               and (q.sales_rep_id = public.sales_rep_saya()
                    or (q.sales_rep_id is null and l.sales_rep_id = public.sales_rep_saya()))))
$$;
alter policy quote_baca on public.quotes to authenticated using (
  public.peran_saya() = 'vonny' or public.boleh_lihat_semua_lead()
  or (public.peran_saya() = 'sales' and public.sales_rep_saya() is not null and (
        sales_rep_id = public.sales_rep_saya()
        or (sales_rep_id is null and exists (select 1 from public.leads l
              where l.id = quotes.lead_id and l.sales_rep_id = public.sales_rep_saya())))));

-- Uji (DEV, transaksi rollback, 28 Sep 2026; counter IX/2026 = 21 sebelum & sesudah, quotes 0):
--   T1  Alfred (sales) INSERT langsung '022/PQ/MCE/IX/2026' (belum dikeluarkan) → DITOLAK P0001;
--       nomor bebas 'ABC-1' → DITOLAK P0001.
--   T2  Alfred INSERT tanpa nomor (RETURNING) → LOLOS, nomor 022 dari counter.
--   T3  alur index.html lama (rpc nomor_penawaran_baru lalu POST /quotes) → LOLOS 023.
--   T4  owner INSERT nomor masa depan 026 → LOLOS (dikecualikan).
--   T5  Iwan simpan_penawaran 3x → 024, 025, 027 (026 dilompati, tidak macet).
--   T6  Iwan untuk pelanggan Alfred → DITOLAK P0001 (aturan berkas 87 tetap).
--   T7  Vonny mewakili Alfred → LOLOS 028, sales_rep_id = 2.
--   T8  Vonny ubah nomor → DITOLAK P0001; ubah kepada (tanpa nomor) → LOLOS. T9 owner ubah nomor → LOLOS.
--   T10 Alfred (sales) melihat 4 penawaran miliknya; T11 Iwan hanya 3 miliknya, penawaran Alfred 0.
--   T12 Alfred → nonaktif (masih tertaut rep 2): quotes 0, quote_lines 0, boleh_lihat_quote false.
--   T13 Alfred → pending: quotes 0, quote_lines 0.
--   T15 nomor_penawaran_format(1000, 2026, 9) = '1000/PQ/MCE/IX/2026' (tidak terpotong).
--   T17 jalur ulang: counter dibuat sementara TIDAK melompat, owner mengisi 029 & 030 lebih dulu →
--       simpan_penawaran bentrok 2x lalu LOLOS 031.
--   Sesudah diterapkan, ulangi temuan review: D1 Alfred nomor 022 DITOLAK; D2 Iwan simpan 3x →
--   022, 023, 024; D3 Vonny → 025; Alfred sales melihat 1, Menik 0; Alfred nonaktif/pending → 0.
