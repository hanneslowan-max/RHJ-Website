-- Berkas 108 (#28, keputusan Hannes opsi a): SET RODA LANGSUNG DI BARIS PO / PENAWARAN / SP.
--
-- Masalah: sales tidak punya akses halaman Produk dan tidak boleh menulis data master
--   product_sets/product_set_components (RLS pset_*/psetc_* = owner/gm/staff), padahal "+ Set" di
--   form PO/penawaran/SP hanya bisa memilih set master → sales tidak bisa memakai harga SET.
--
-- Solusi "set langsung di baris" (set inline):
--   Baris PO:        jenis 'barang', product_id NULL, set_id NULL, set_komponen = [{product_id,qty,urut}]
--                    (qty per 1 set), qty = jumlah set (bulat), harga = harga PER SET dari PO customer,
--                    deskripsi mis. 'Set 03 PUR 4" (2 hidup + 2 mati)'. Tampil "1 set @harga".
--   Baris penawaran: quote_lines.set_komponen (kolom BARU) dengan aturan yang sama, satuan 'set'.
--   SP tanpa PO:     tidak ada yang disimpan sebagai set — FE langsung memecah ke pcs.
--   Tidak ada baris product_sets/product_set_components yang dibuat; hak tulis data master TIDAK berubah.
--
-- Penegakan di DB (bukan hanya FE):
-- (1) set_inline_rapi(jsonb) [internal]: menormalkan snapshot → [{product_id,qty,urut}] per produk
--     (qty dijumlah per produk, harga_nett & kunci lain DIBUANG — bobot pembagian harga tidak bisa
--     disisipkan klien). label_set_inline(jsonb): 'Set <tipe> (<kombinasi>)' untuk deskripsi kosong.
-- (2) jaga_set_baris_po (trigger po_lines_set_snapshot) diperluas: set_id NULL + set_komponen terisi
--     = set inline → dinormalkan lalu WAJIB lolos periksa_komposisi_set (berkas 94: tepat 4 pcs, qty
--     bulat, satu kategori + merek + tipe_roda, fungsi Rem/Hidup/Mati tercatat, satu produk per fungsi,
--     kombinasi 4R/4H/4M/2R+2H/2R+2M/2H+2M, produk ada & bukan usulan). Snapshot tidak bisa diubah
--     langsung sesudah tersimpan; putuskan_ubah (rhj.usul='on') membawanya apa adanya (sama dengan set
--     master — snapshot di jalur usul hanya bisa berasal dari baris tersimpan PO itu sendiri, karena
--     po_baris_usul_lengkap tidak pernah mengambil set_komponen dari payload).
-- (3) jaga_jenis_baris: baris barang tanpa product_id sah bila set_id ATAU set_komponen terisi.
-- (4) CHECK po_lines: po_lines_set_qty_bulat & po_lines_set_bukan_produk berlaku juga untuk set inline;
--     po_lines_set_komponen_larik (set_komponen harus larik JSON).
-- (5) po_baris_usul_lengkap: snapshot dibuang bila payload mengubah baris jadi produk/biaya.
--     periksa_baris_po_usul: baris set inline dianggap "menunjuk set"; jumlah set inline wajib bulat.
-- (6) quote_lines.set_komponen + CHECK quote_lines_set_inline + trigger quote_lines_set_inline
--     (jaga_set_baris_quote) — aturan sama; simpan_penawaran menerima set_komponen.
-- (7) pilihan_tipe_roda(): daftar produk roda berfungsi Rem/Hidup/Mati (aktif, bukan usulan) beserta
--     kunci tipe (kategori|merek|tipe_roda tanpa spasi — definisi "tipe sama" yang dipakai
--     periksa_komposisi_set) untuk isian "+ Set" di FE. SECURITY INVOKER → ikut RLS products
--     (boleh_lihat_produk; sales boleh). Tanpa harga.
--
-- Harga (FE, index.html spBarisDariPo/alokasiSetSen/bobotSetInline): nilai bersih baris set (sesudah
--   diskon) dibagi ke komponen SEBANDING qty × price list berlaku (hargaListProduk) masing-masing,
--   komponen terakhir menyerap sisa, lalu dipecah pecahNettSen (maks. 2 baris SP per komponen,
--   selisih 1 sen/Rp 1) → jumlah SP = nilai baris PO persis sampai sen; periksa_total_sp tetap lolos.
--   Karena sebanding, rasio nett/list tiap roda sama = harga set / jumlah list; set di bawah price list
--   → tiap roda di bawah list → SP menunggu GM seperti biasa (isi_harga_list + gerbang harga).
--   Ada komponen tanpa price list → dibagi rata per pcs (tidak ada dasar pembanding).
--   Set master tetap dibagi berbobot harga_nett definisinya (berkas 94) — perilaku lama tidak diubah.
--
-- Data: aditif. DEV sebelum migrasi: po_lines 55 (0 set inline), quote_lines 0. Semua CHECK lolos.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 29 Sep 2026 (migrasi berkas108_set_inline_baris).
-- Belum ke produksi. Urutan di produksi: sesudah berkas 94 & 107; berkas ini DULU, baru index.html baru.
-- Membalik: drop trigger quote_lines_set_inline; drop constraint quote_lines_set_inline,
--   po_lines_set_komponen_larik; kembalikan 2 CHECK po_lines, jaga_set_baris_po, jaga_jenis_baris,
--   po_baris_usul_lengkap, periksa_baris_po_usul, simpan_penawaran ke badan berkas 94/87/85
--   (hanya bila tidak ada baris set inline tersimpan).

-- 1) Helper snapshot inline
create or replace function public.set_inline_rapi(p_komponen jsonb)
returns jsonb language sql immutable set search_path = public as $$
  select case when p_komponen is null or jsonb_typeof(p_komponen) <> 'array' then p_komponen else (
    select coalesce(jsonb_agg(jsonb_build_object('product_id', g.pid, 'qty', g.qty, 'urut', g.urut)
                              order by g.urut, g.pid), '[]'::jsonb)
      from (select nullif(x->>'product_id', '')::bigint as pid,
                   sum(coalesce(nullif(x->>'qty', '')::numeric, 0)) as qty,
                   min(i)::int as urut
              from jsonb_array_elements(p_komponen) with ordinality o(x, i)
             where jsonb_typeof(x) = 'object'
             group by 1) g) end
$$;

create or replace function public.label_set_inline(p_komponen jsonb)
returns text language sql stable set search_path = public as $$
  select 'Set ' || coalesce(max(public.tipe_roda(p.kode)), 'roda') || ' ('
         || array_to_string(array_remove(array[
              case when sum(k.qty) filter (where p.fungsi = 'Rem / Brake') > 0
                   then trim_scale(sum(k.qty) filter (where p.fungsi = 'Rem / Brake')) || ' rem' end,
              case when sum(k.qty) filter (where p.fungsi = 'Hidup / Swivel') > 0
                   then trim_scale(sum(k.qty) filter (where p.fungsi = 'Hidup / Swivel')) || ' hidup' end,
              case when sum(k.qty) filter (where p.fungsi = 'Mati / Rigid') > 0
                   then trim_scale(sum(k.qty) filter (where p.fungsi = 'Mati / Rigid')) || ' mati' end
            ], null), ' + ') || ')'
    from jsonb_to_recordset(p_komponen) k(product_id bigint, qty numeric)
    join public.products p on p.id = k.product_id
$$;

-- 2) Snapshot + jaga set di po_lines (master & inline)
create or replace function public.jaga_set_baris_po()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_usul boolean := coalesce(current_setting('rhj.usul', true), '') = 'on';
  v_aktif boolean; v_nama text; v_pesan text;
begin
  if new.set_id is null then
    -- #28 (berkas 108): set inline — isi set ditulis langsung di baris, tanpa data master set.
    if new.set_komponen is null then
      return new;
    end if;
    if tg_op = 'UPDATE' and old.set_id is null and new.set_komponen is not distinct from old.set_komponen then
      return new;
    end if;
    if tg_op = 'UPDATE' and not v_usul then
      raise exception 'Isi set di baris PO adalah catatan saat PO dibuat dan tidak bisa diubah langsung.';
    end if;
    if jsonb_typeof(new.set_komponen) <> 'array' then
      raise exception 'Format isi set tidak dikenal.';
    end if;
    -- putuskan_ubah: snapshot di jalur usul hanya bisa berasal dari baris tersimpan PO ini
    -- (po_baris_usul_lengkap tak pernah mengambilnya dari payload) → dibawa apa adanya.
    if v_usul then
      return new;
    end if;
    new.set_komponen := public.set_inline_rapi(new.set_komponen);
    v_pesan := public.periksa_komposisi_set(new.set_komponen);
    if v_pesan is not null then
      raise exception 'Set di baris PO tidak sah: %', v_pesan;
    end if;
    if coalesce(btrim(new.deskripsi), '') = '' then
      new.deskripsi := public.label_set_inline(new.set_komponen);
    end if;
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

-- 3) jaga_jenis_baris: baris barang tanpa produk sah bila set_id ATAU set_komponen terisi
create or replace function public.jaga_jenis_baris()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if new.jenis = 'biaya' then
    if new.product_id is not null then
      raise exception 'Baris biaya tidak boleh menunjuk produk. Ongkos kirim dan '
                      'packing bukan barang, dan tidak boleh masuk master produk.';
    end if;
    if coalesce(btrim(new.deskripsi), '') = '' then
      raise exception 'Baris biaya wajib punya keterangan — misalnya "Ongkos kirim Jakarta".';
    end if;
  else
    -- #1: baris SET (khusus po_lines) — barang tanpa product_id tapi menunjuk set. Dilewatkan;
    -- pemecahan ke pcs (yang menunjuk produk) terjadi saat SP dibuat.
    -- #28 (berkas 108): juga set inline (set_id NULL, set_komponen terisi) — isinya dijaga
    -- jaga_set_baris_po. sales_order_lines tak punya kedua kolom → selalu NULL di sini.
    if (to_jsonb(new)->>'set_id') is not null
       or jsonb_typeof(to_jsonb(new)->'set_komponen') = 'array' then
      return new;
    end if;
    if new.product_id is null
       and not (tg_op = 'UPDATE' and old.jenis = 'barang' and old.product_id is null) then
      raise exception 'Baris barang harus menunjuk produk di master. Kalau barangnya '
                      'belum ada, buat dulu sebagai usulan item baru — dari situ ia '
                      'masuk antrean pengesahan dan tersambung ke master. Baris barang '
                      'berupa teks bebas tidak pernah sampai ke mana-mana.'
        using errcode = '23514';
    end if;
    if new.product_id is null and coalesce(btrim(new.deskripsi), '') = '' then
      raise exception 'Baris barang harus punya produk atau, kalau produknya belum ada '
                      'di master, keterangan barangnya. Baris tanpa keduanya tidak bisa '
                      'ditelusuri siapa pun nanti.';
    end if;
  end if;
  return new;
end $function$;

-- 4) CHECK po_lines: aturan baris set berlaku juga untuk set inline
alter table public.po_lines drop constraint po_lines_set_qty_bulat;
alter table public.po_lines drop constraint po_lines_set_bukan_produk;
alter table public.po_lines
  add constraint po_lines_set_qty_bulat check (
    (set_id is null and set_komponen is null) or qty = trunc(qty)),
  add constraint po_lines_set_bukan_produk check (
    (set_id is null and set_komponen is null) or (product_id is null and jenis = 'barang')),
  add constraint po_lines_set_komponen_larik check (
    set_komponen is null or jsonb_typeof(set_komponen) = 'array');

-- 5) Helper minta-ubah PO
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
    -- #28 (berkas 108): baris diubah jadi produk/biaya → bukan baris set lagi (inline maupun master)
    if nullif(x->>'product_id', '') is not null or coalesce(x->>'jenis', '') = 'biaya' then
      b := b - 'set_komponen';
    end if;
    hasil := hasil || jsonb_build_array(b || (x - 'set_komponen' - 'po_id'));   -- snapshot TAK PERNAH dari payload
  end loop;
  return hasil;
end $$;

create or replace function public.periksa_baris_po_usul(p_baris jsonb)
returns void language plpgsql immutable set search_path = public as $$
declare x jsonb; i int := 0; q numeric; h numeric; d numeric; t text; bruto numeric; v_set boolean;
begin
  for x in select value from jsonb_array_elements(coalesce(p_baris, '[]'::jsonb)) loop
    i := i + 1;
    q := nullif(x->>'qty', '')::numeric;
    h := coalesce(nullif(x->>'harga', '')::numeric, 0);
    d := coalesce(nullif(x->>'diskon', '')::numeric, 0);
    t := coalesce(nullif(x->>'diskon_tipe', ''), 'rp');
    -- #28: baris set = set master (set_id) ATAU set inline (set_komponen larik)
    v_set := nullif(x->>'set_id', '') is not null or jsonb_typeof(x->'set_komponen') = 'array';
    if q is null or q <= 0 then
      raise exception 'Baris %: qty harus lebih dari 0.', i;
    end if;
    if v_set and q <> trunc(q) then
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
       and nullif(x->>'product_id', '') is null and not v_set then
      raise exception 'Baris %: baris barang harus menunjuk produk atau set.', i;
    end if;
  end loop;
end $$;

-- 6) Penawaran: snapshot set inline di quote_lines
alter table public.quote_lines add column if not exists set_komponen jsonb;
comment on column public.quote_lines.set_komponen is
  '#28 (berkas 108): isi set inline [{product_id,qty,urut}] (qty per 1 set) — set yang disusun langsung '
  'di baris penawaran tanpa data master set. NULL = bukan set inline. Dijaga trigger quote_lines_set_inline.';
comment on column public.po_lines.set_komponen is
  '#1 (berkas 94) / #28 (berkas 108): isi set baris PO. Set master (set_id terisi): snapshot definisi '
  '[{product_id,qty,harga_nett,urut}] diisi trigger. Set inline (set_id NULL): [{product_id,qty,urut}] '
  'dari penginput, dinormalkan & wajib sah (periksa_komposisi_set). Tidak bisa diubah langsung.';
alter table public.quote_lines
  add constraint quote_lines_set_inline check (
    set_komponen is null or (set_id is null and product_id is null and qty = trunc(qty)
                             and jsonb_typeof(set_komponen) = 'array'));

create or replace function public.jaga_set_baris_quote()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_pesan text;
begin
  if new.set_komponen is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.set_komponen is not distinct from old.set_komponen then
    return new;
  end if;
  if jsonb_typeof(new.set_komponen) <> 'array' then
    raise exception 'Format isi set tidak dikenal.';
  end if;
  new.set_komponen := public.set_inline_rapi(new.set_komponen);
  v_pesan := public.periksa_komposisi_set(new.set_komponen);
  if v_pesan is not null then
    raise exception 'Set di baris penawaran tidak sah: %', v_pesan;
  end if;
  new.satuan := 'set';
  if coalesce(btrim(new.deskripsi), '') in ('', '—') then
    new.deskripsi := public.label_set_inline(new.set_komponen);
  end if;
  return new;
end $$;
drop trigger if exists quote_lines_set_inline on public.quote_lines;
create trigger quote_lines_set_inline before insert or update on public.quote_lines
  for each row execute function public.jaga_set_baris_quote();

create or replace function public.simpan_penawaran(p_kepala jsonb, p_baris jsonb)
returns jsonb language plpgsql set search_path to 'public' as $function$
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
  return jsonb_build_object('id', v_id, 'nomor', v_nomor);
end $function$;

-- 7) Pilihan tipe roda untuk isian "+ Set" (tanpa harga; ikut RLS products)
create or replace function public.pilihan_tipe_roda()
returns table (kunci text, kategori text, brand text, tipe text, product_id bigint, kode text,
               fungsi text, diameter_mm numeric, bahan text)
language sql stable security invoker set search_path = public as $$
  select coalesce(p.kategori, '') || '|' || coalesce(p.brand, '') || '|'
           || replace(coalesce(public.tipe_roda(p.kode), ''), ' ', ''),
         p.kategori, p.brand, public.tipe_roda(p.kode), p.id, p.kode, p.fungsi, p.diameter_mm, p.bahan
    from public.products p
   where p.fungsi in ('Rem / Brake', 'Hidup / Swivel', 'Mati / Rigid')
     and coalesce(p.aktif, true) and not coalesce(p.usulan, false)
     and public.tipe_roda(p.kode) is not null
   order by p.brand, public.tipe_roda(p.kode), p.fungsi, p.kode
$$;

-- 8) Hak
revoke execute on function public.pilihan_tipe_roda(), public.label_set_inline(jsonb) from public, anon;
grant execute on function public.pilihan_tipe_roda(), public.label_set_inline(jsonb) to authenticated;
revoke execute on function public.set_inline_rapi(jsonb) from public, anon, authenticated;   -- internal
revoke execute on function public.jaga_set_baris_quote() from public, anon;
