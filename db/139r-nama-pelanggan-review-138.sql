-- ═══════════════════════════════════════════════════════════════════════
-- 139r · Tindak lanjut review berkas 138 (temuan keamanan #2: nama & pemegang pelanggan)
-- (nomor 139r: jatah nomor sesi ini 120–139; "r" = review 138; diurutkan sesudah 139p dan sebelum berkas EHC 140+.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  1. (tinggi) Kepada SP / nama pelanggan ditulis "P.T. X", "C. V. X", "P T X" → kuncinya "p t x", sedangkan nama yang
--     tersimpan ("PT X", dirapikan rhj_nama_rapi) berkunci "x". Cek Vonny (no. 10a) lolos dan lengkapi_pelanggan_sp /
--     buat_pelanggan_baru membuat kembaran persis untuk sales penyerang; pemeriksaan 8a hanya berjalan untuk sales.
--     → kunci_nama_pelanggan membuang bentuk badan usaha berhuruf tunggal (p t · c v · u d · p d · t b · t b k);
--       ketikan dibandingkan sesudah dirapikan (kunci(rhj_nama_rapi(x)) = cara nama memang disimpan) di
--       cek_kelayakan_vonny, lengkapi_pelanggan_sp, buat_pelanggan_baru, nama_pelanggan_kembar, jaga_pelanggan_sp_sales;
--       8a (customers_tolak_nama_ganda) berlaku untuk SEMUA peran selain owner/GM/staff (dulu hanya sales) — mis. Vonny
--       lewat lengkapi_pelanggan_sp.
--  2. Karakter tak terlihat (zero-width space, word joiner, BOM, …) dan huruf Kiril/Yunani yang mirip huruf Latin →
--     kembaran yang tampak sama persis di layar & dokumen. → teks_tanpa_format (NFKC + karakter format dibuang) dipakai
--     kunci_nama_pelanggan & rhj_nama_rapi; kunci memetakan huruf Kiril/Yunani yang mirip ke huruf Latin; nama
--     pelanggan & Kepada SP yang memuat huruf non-Latin ditolak untuk selain owner/GM/staff (P0001); Kepada SP
--     dibersihkan saat disimpan (trigger so_a_kepada_bersih).
--  4. Sales POST /customers dengan sales_rep_id sales lain / Office → tersimpan (pemegang ditentukan di luar PO).
--     → customers_sales_bawaan menolak (P0001); pelanggan baru buatan sales selalu miliknya (= buat_pelanggan_baru).
--  5/7/11. lengkapi_pelanggan_sp menjawab aturan bisnis "dipegang sales lain" dengan 42501 (HTTP 403 → layar keluar
--     sesudah 3 kali). → P0001; juga customers_jaga_sales, buat_pelanggan_baru (sales untuk sales lain), dan
--     jaga_pelanggan_sp_sales. 42501 tinggal untuk pemeriksaan peran. Layar memeriksa kelayakan dulu (index.html).
--  6/10. Nama kembar milik dua sales: alasan "nama_sales_lain" menyarankan memindahkan pelanggan/mengganti sales SP
--     walau sales SP sendiri punya pelanggan bernama sama; tidak ada jalan menautkan SP ke pelanggan tertentu.
--     → pesan menyebut kedua pelanggan; RPC baru owner/GM: kandidat_pelanggan_sp + tautkan_pelanggan_sp (ATURAN B
--       "pelanggan SP … diubah owner/GM") — hanya pelanggan yang nama/No. HP-nya cocok, milik sales SP atau belum
--       bertuan, bukan daftar hitam, dan sama dengan pelanggan PO-nya.
--  Tidak di berkas ini: 3 (PO pura-pura lalu dibatalkan tetap mengklaim pelanggan — pertanyaan Q28 untuk Hannes),
--  12 (SP langsung memilih kembaran lama yang belum bertuan — masuk Q21), 8/9 (teks & pemilih di layar — index.html),
--  pencocokan nama ke pelanggan daftar hitam (sp_pelanggan_hitam — berkas 139s).
-- Tambalan pada definisi hidup + pemeriksaan jangkar (berhenti bila bentuknya tidak seperti yang diharapkan; hasil
-- tambalan dibandingkan balik dengan definisi lama). Tidak ada data yang diubah (indeks kunci nama dibangun ulang);
-- tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139y: menjalankannya ulang sendirian menurunkan fungsi yang diperbarui berkas sesudahnya
--      (review 139v no. 2). Menjalankan ulang seluruh rantai 138 → 139y berurutan: `set rhj.ulang_rantai = 'on';` dulu.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '139r: berkas ini sudah disusul 139y — jangan dijalankan ulang sendirian (jalankan ulang seluruh rantai '
                    '138 → 139y berurutan sesudah set rhj.ulang_rantai = ''on'').';
  end if;
end $$;

-- 0 · prasyarat (review 139r no. 9: `sort -V` menaruh 139r sebelum 139): 138 & 139 sudah dijalankan
do $$ begin
  if to_regprocedure('public.kunci_nama_pelanggan(text)') is null
     or position('v_hitam_alasan' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0 then
    raise exception '139r: jalankan 138 dan 139 dulu.';
  end if;
end $$;

-- A · teks bersih: NFKC + karakter format (tak terlihat) dibuang — soft hyphen, zero-width, penanda arah, word joiner,
--     variation selector, BOM, pengisi Hangul, karakter tag
create or replace function public.teks_tanpa_format(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(normalize(p, NFKC),
    '[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ\U000e0000-\U000e0fff]',
    '', 'g')
$$;
comment on function public.teks_tanpa_format(text) is '139r: NFKC + karakter format (tak terlihat) dibuang.';

-- huruf/angka di luar huruf Latin (dasar, Latin-1, Extended-A/B, Extended Additional) & angka 0-9
create or replace function public.ada_huruf_non_latin(p text)
returns boolean language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(regexp_replace(coalesce(public.teks_tanpa_format(p), ''), '[^[:alnum:]]', '', 'g'),
                        '[0-9A-Za-zªºÀ-ÖØ-öø-ɏḀ-ỿ]', '', 'g') <> ''
$$;
comment on function public.ada_huruf_non_latin(text) is '139r: true bila ada huruf/angka non-Latin (mis. Kiril/Yunani).';

-- B · kunci nama: teks bersih, huruf Kiril/Yunani yang mirip dipetakan, badan usaha berhuruf tunggal dibuang
create or replace function public.kunci_nama_pelanggan(p text)
returns text language sql immutable set search_path = public as $$
  select coalesce(string_agg(k, ' ' order by n), '')
    from regexp_split_to_table(
           btrim(regexp_replace(regexp_replace(
             ' ' || regexp_replace(
                      translate(lower(coalesce(public.teks_tanpa_format(p), '')),
                                'аеорсухіјѕкмнтвӏԁԛԝαβεζηικμνορτυχ', 'aeopcyxijskmhtbldqwabezhikmnoptyx'),
                      '[^[:alnum:]]+', ' ', 'g') || ' ',
             ' (t b k|p t|c v|u d|p d|t b)(?= )', ' ', 'g'),
           ' +', ' ', 'g')), ' ')
         with ordinality as s(k, n)
   where k <> '' and k not in ('pt','cv','ud','pd','tb','tbk','toko')
$$;
-- indeks ekspresi memakai fungsi ini → dibangun ulang (DEV: tidak ada kunci yang berubah, uji 9 Okt)
reindex index public.customers_kunci_nama_idx;
reindex index public.customers_kunci_nama_lama_idx;

-- C · tambalan definisi hidup (jangkar harus muncul tepat n kali; dilewati bila tambalannya sudah ada)
do $$
declare
  t text[];
  d text; d2 text; n int;
  daftar text[] := array[
    -- rhj_nama_rapi: nama tersimpan bersih dari karakter tak terlihat
    ['public.rhj_nama_rapi(text)', $a$s := btrim(regexp_replace(p, $a$,
     $b$s := btrim(regexp_replace(public.teks_tanpa_format(p), $b$, '1'],
    -- buat_pelanggan_baru: kunci dari nama yang dirapikan; sales untuk sales lain → P0001
    ['public.buat_pelanggan_baru(text,text,text,bigint)', $a$v_kunci := public.kunci_nama_pelanggan(v_nama);$a$,
     $b$v_kunci := public.kunci_nama_pelanggan(public.rhj_nama_rapi(v_nama));   -- 139r: = nama yang disimpan$b$, '1'],
    ['public.buat_pelanggan_baru(text,text,text,bigint)',
     $a$raise exception 'Sales hanya bisa menambah pelanggan baru untuk dirinya sendiri.' using errcode = '42501';$a$,
     $b$raise exception 'Sales hanya bisa menambah pelanggan baru untuk dirinya sendiri.' using errcode = 'P0001';$b$, '1'],
    -- nama_pelanggan_kembar: kunci dari nama yang dirapikan
    ['public.nama_pelanggan_kembar(text,bigint)', $a$declare v_k text := public.kunci_nama_pelanggan(p_nama);$a$,
     $b$declare v_k text := public.kunci_nama_pelanggan(public.rhj_nama_rapi(p_nama));   -- 139r$b$, '1'],
    -- customers_jaga_sales: aturan bisnis → P0001
    ['public.customers_jaga_sales()', $a$errcode = '42501'$a$, $b$errcode = 'P0001'$b$, '2'],
    -- jaga_pelanggan_sp_sales: Kepada dirapikan dulu; aturan bisnis → P0001
    ['public.jaga_pelanggan_sp_sales()',
     $a$and public.kunci_nama_pelanggan(new.kepada) is distinct from public.kunci_nama_pelanggan(v_nama)$a$,
     $b$and public.kunci_nama_pelanggan(public.rhj_nama_rapi(new.kepada)) is distinct from public.kunci_nama_pelanggan(v_nama)$b$, '1'],
    ['public.jaga_pelanggan_sp_sales()',
     $a$or public.kunci_nama_pelanggan(new.kepada) is distinct from public.kunci_nama_pelanggan(v_lama)$a$,
     $b$or public.kunci_nama_pelanggan(public.rhj_nama_rapi(new.kepada)) is distinct from public.kunci_nama_pelanggan(v_lama)$b$, '1'],
    ['public.jaga_pelanggan_sp_sales()', $a$using errcode = '42501'$a$, $b$using errcode = 'P0001'$b$, '5'],
    -- customers_tolak_nama_ganda: huruf non-Latin & 8a untuk semua peran selain owner/GM/staff
    ['public.customers_tolak_nama_ganda()', $a$  if v_peran <> 'sales' then return new; end if;$a$,
     $b$  -- 139r (review 138 no. 2): huruf non-Latin (mis. Kiril/Yunani yang mirip huruf biasa) — selain owner/GM/staff ditolak
  if coalesce(v_peran, '') not in ('owner','gm','staff') and (tg_op = 'INSERT' or new.nama is distinct from old.nama)
     and public.ada_huruf_non_latin(new.nama) then
    raise exception 'Nama pelanggan "%" memuat huruf di luar huruf Latin biasa (mis. huruf Kiril/Yunani yang mirip). Ketik '
                    'ulang namanya dengan huruf biasa; bila memang perlu, minta owner/GM/staff.', new.nama
      using errcode = 'P0001';
  end if;
  -- 139r (review 138 no. 1): 8a berlaku untuk semua peran selain owner/GM/staff (mis. Vonny lewat lengkapi_pelanggan_sp)
  if v_peran in ('owner','gm','staff') then return new; end if;$b$, '1'],
    -- cek_kelayakan_vonny: kunci dari Kepada yang dirapikan; kembar milik dua sales; teks tindakan
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$v_kunci := public.kunci_nama_pelanggan(s.kepada);$a$,
     $b$v_kunci := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));   -- 139r: = nama yang disimpan$b$, '1'],
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$  v_hitam_alasan text;$a$,
     $b$  v_hitam_alasan text;
  v_milik    public.customers;   -- 139r$b$, '1'],
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$                   || ' (tab Pelanggan) atau mengganti sales SP.';$a$,
     $b$                   || ' (tab Pelanggan), atau menautkan SP ini ke pelanggan lain yang benar (Tautkan ke pelanggan '
                   || 'tertentu — laci cek atau detail SP).';$b$, '1'],
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$          kode := 'nama_sales_lain';
          pesan := 'Nama "' || coalesce(s.kepada, '') || '" cocok dengan pelanggan "' || v_ada.nama || '" yang dipegang sales '
                || coalesce(v_sales, 'lain') || ', bukan sales SP ini (' || coalesce(v_sales_sp, '—') || ').';
          tindakan := 'Owner/GM memutuskan: pindahkan pelanggannya ke ' || coalesce(v_sales_sp, 'sales SP')
                   || ' di tab Pelanggan, atau ganti sales SP ke ' || coalesce(v_sales, 'pemegangnya')
                   || '. Sesudah itu Vonny bisa meloloskan.';$a$,
     $b$          kode := 'nama_sales_lain';
          -- 139r (review 138 no. 6/10): sales SP juga punya pelanggan bernama sama (atau ada yang belum bertuan) →
          -- sebut keduanya; owner/GM menautkan SP ke pelanggan yang benar (tautkan_pelanggan_sp)
          v_milik := null;
          select c.* into v_milik from public.customers c
           where c.id <> v_ada.id and not c.blacklist
             and (c.sales_rep_id is null or c.sales_rep_id = s.sales_rep_id)
             and (public.kunci_nama_pelanggan(c.nama) = v_kunci
                  or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci))
           order by case when c.sales_rep_id is not null then 0 else 1 end, c.id
           limit 1;
          if v_milik.id is not null then
            pesan := 'Nama "' || coalesce(s.kepada, '') || '" cocok dengan dua data pelanggan: "' || v_ada.nama
                  || '" (dipegang sales ' || coalesce(v_sales, 'lain') || ') dan "' || v_milik.nama || '" ('
                  || case when v_milik.sales_rep_id is null then 'belum bertuan'
                          else 'milik sales SP ini, ' || coalesce(v_sales_sp, '—') end || ').';
            tindakan := 'Owner/GM menautkan SP ini ke pelanggan yang benar (Tautkan ke pelanggan tertentu — laci cek atau '
                     || 'detail SP). Bila SP ini memang untuk "' || v_ada.nama || '", pindahkan pelanggannya ke '
                     || coalesce(v_sales_sp, 'sales SP') || ' di tab Pelanggan. Sesudah itu Vonny bisa meloloskan.';
          else
            pesan := 'Nama "' || coalesce(s.kepada, '') || '" cocok dengan pelanggan "' || v_ada.nama || '" yang dipegang sales '
                  || coalesce(v_sales, 'lain') || ', bukan sales SP ini (' || coalesce(v_sales_sp, '—') || ').';
            tindakan := 'Owner/GM memutuskan: bila memang pelanggan yang sama, pindahkan pelanggannya ke '
                     || coalesce(v_sales_sp, 'sales SP') || ' di tab Pelanggan; bila perusahaan/orang lain, ubah Kepada '
                     || 'lewat Minta ubah SP (beri pembeda, mis. kota/cabang). Sesudah itu Vonny bisa meloloskan.';
          end if;$b$, '1'],
    -- lengkapi_pelanggan_sp: kunci dari Kepada yang dirapikan; aturan bisnis → P0001; kembar milik dua sales
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)', $a$v_kunci := public.kunci_nama_pelanggan(s.kepada);$a$,
     $b$v_kunci := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));   -- 139r: = nama yang disimpan$b$, '1'],
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)', $a$  v_sales  text;$a$,
     $b$  v_sales  text;
  v_milik  public.customers;   -- 139r$b$, '1'],
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)', $a$      raise exception '% SP % cocok dengan pelanggan "%" yang dipegang sales %, bukan sales SP ini. '
                      'Pindahkan dulu pelanggannya ke sales SP (tab Pelanggan) atau ganti sales SP — owner/GM.',
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id)
        using errcode = '42501';$a$,
     $b$      -- 139r (review 138 no. 5–7/10/11): aturan bisnis → P0001 (bukan 42501 = HTTP 403 yang dihitung batas keluar
      -- layar); sales SP juga punya pelanggan bernama sama → sebut keduanya, owner/GM yang menautkan (tautkan_pelanggan_sp)
      if v_cocok = 'nama' then
        select c.* into v_milik from public.customers c
         where c.id <> v_ada.id and not c.blacklist
           and (c.sales_rep_id is null or c.sales_rep_id = s.sales_rep_id)
           and (public.kunci_nama_pelanggan(c.nama) = v_kunci
                or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci))
         order by case when c.sales_rep_id is not null then 0 else 1 end, c.id
         limit 1;
      end if;
      if v_milik.id is not null then
        raise exception 'Nama SP % cocok dengan dua data pelanggan: "%" (dipegang sales %) dan "%" (%). Owner/GM menautkan '
                        'SP ini ke pelanggan yang benar (Tautkan ke pelanggan tertentu — laci cek atau detail SP).',
                        s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id), v_milik.nama,
                        case when v_milik.sales_rep_id is null then 'belum bertuan' else 'milik sales SP ini' end
          using errcode = 'P0001';
      end if;
      raise exception '% SP % cocok dengan pelanggan "%" yang dipegang sales %, bukan sales SP ini. Bila memang pelanggan '
                      'yang sama, owner/GM memindahkan pelanggannya ke sales SP (tab Pelanggan); bila perusahaan/orang '
                      'lain, ubah Kepada lewat Minta ubah SP (beri pembeda, mis. kota/cabang).',
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id)
        using errcode = 'P0001';$b$, '1']
  ];
begin
  foreach t slice 1 in array daftar loop
    d := pg_get_functiondef(t[1]::regprocedure);
    if position(t[3] in d) > 0 then continue; end if;   -- sudah ditambal
    n := (length(d) - length(replace(d, t[2], ''))) / length(t[2]);
    if n <> t[4]::int then
      raise exception '139r: % — jangkar "%" muncul % kali (harus %).', t[1], left(t[2], 70), n, t[4];
    end if;
    execute replace(d, t[2], t[3]);
    d2 := pg_get_functiondef(t[1]::regprocedure);
    if replace(d2, t[3], t[2]) <> d then raise exception '139r: % — hasil tambalan tidak sesuai.', t[1]; end if;
  end loop;
end $$;

-- D · (no. 4) pelanggan baru buatan sales selalu miliknya — sales lain / Office ditolak (P0001, = buat_pelanggan_baru)
create or replace function public.customers_sales_bawaan()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and public.peran_saya() = 'sales' then
    if new.sales_rep_id is not null and new.sales_rep_id is distinct from public.sales_rep_saya() then
      raise exception 'Sales hanya bisa menambah pelanggan untuk dirinya sendiri — pelanggan baru yang Anda tambahkan '
                      'otomatis menjadi milik Anda. Pemindahan ke sales lain diputuskan owner, GM, atau staff.'
        using errcode = 'P0001';
    end if;
    new.sales_rep_id := public.sales_rep_saya();
  end if;
  return new;
end $$;

-- E · (no. 2) Kepada SP dibersihkan dari karakter tak terlihat; huruf non-Latin hanya owner/GM/staff
create or replace function public.sp_kepada_bersih()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.kepada is null or (tg_op = 'UPDATE' and new.kepada is not distinct from old.kepada) then return new; end if;
  new.kepada := btrim(public.teks_tanpa_format(new.kepada));
  if auth.uid() is not null and coalesce(public.peran_saya(), '') not in ('owner','gm','staff')
     and public.ada_huruf_non_latin(new.kepada) then
    raise exception 'Kepada "%" memuat huruf di luar huruf Latin biasa (mis. huruf Kiril/Yunani yang mirip). Ketik ulang '
                    'dengan huruf biasa; bila memang perlu, minta owner/GM/staff.', new.kepada
      using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function public.sp_kepada_bersih() from public, anon, authenticated;
create or replace trigger so_a_kepada_bersih
  before insert or update of kepada on public.sales_orders
  for each row execute function public.sp_kepada_bersih();

-- F · (no. 6/10) owner/GM menautkan SP yang belum tertaut ke pelanggan tertentu
--     syarat (= cek_kelayakan_vonny / lengkapi_pelanggan_sp): nama (sesudah dirapikan; nama atau nama asli) atau No. HP
--     cocok, pelanggan milik sales SP atau belum bertuan, bukan daftar hitam, sama dengan pelanggan PO-nya bila ada.
create or replace function public.kandidat_pelanggan_sp(p_so bigint)
returns table(id bigint, nama text, sales text, cocok text, bisa boolean, alasan text)
language plpgsql stable security definer set search_path = public as $$
declare s public.sales_orders; v_k text; v_hp text; v_po_cust bigint;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner/GM yang menautkan SP ke pelanggan tertentu.' using errcode = '42501';
  end if;
  select * into s from public.sales_orders x where x.id = p_so;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002'; end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));
  if char_length(coalesce(v_k, '')) < 2 then v_k := null; end if;
  v_hp := public.hp_baku(s.telp);
  if s.po_id is not null then
    select p.customer_id into v_po_cust from public.purchase_orders p where p.id = s.po_id;
  end if;
  return query
    with c as (
      select x.id, x.nama, sr.nama as sales,
             case when v_k is not null and (public.kunci_nama_pelanggan(x.nama) = v_k
                       or (x.nama_lama is not null and public.kunci_nama_pelanggan(x.nama_lama) = v_k))
                  then 'nama' else 'hp' end as cocok,
             case when x.blacklist then 'pelanggan daftar hitam'
                  when x.sales_rep_id is not null and s.sales_rep_id is not null and x.sales_rep_id <> s.sales_rep_id
                    then 'dipegang sales ' || coalesce(sr.nama, 'lain') || ', bukan sales SP ini'
                  when v_po_cust is not null and v_po_cust <> x.id then 'PO SP ini atas nama pelanggan lain'
             end as alasan
        from public.customers x left join public.sales_reps sr on sr.id = x.sales_rep_id
       where (v_k is not null and (public.kunci_nama_pelanggan(x.nama) = v_k
                                   or (x.nama_lama is not null and public.kunci_nama_pelanggan(x.nama_lama) = v_k)))
          or (v_hp is not null and x.hp = v_hp))
    select c.id, c.nama, c.sales, c.cocok, c.alasan is null, c.alasan
      from c
     order by (c.alasan is null) desc, (c.cocok = 'nama') desc, c.id
     limit 10;
end $$;
revoke all on function public.kandidat_pelanggan_sp(bigint) from public, anon;
grant execute on function public.kandidat_pelanggan_sp(bigint) to authenticated;

create or replace function public.tautkan_pelanggan_sp(p_so bigint, p_customer bigint, p_industri text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s       public.sales_orders;
  c       public.customers;
  v_ind   text := nullif(btrim(coalesce(p_industri, '')), '');
  v_k     text;
  v_hp    text;
  v_po    bigint;
  v_sales text;
  v_pakai boolean := true;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner/GM yang menautkan SP ke pelanggan tertentu.' using errcode = '42501';
  end if;
  if v_ind is not null and v_ind not in ('Otomotif','Non Otomotif','Bengkel Otomotif') then
    raise exception 'Kategori industri hanya Otomotif, Non Otomotif, atau Bengkel Otomotif.' using errcode = '22023';
  end if;
  select * into s from public.sales_orders where id = p_so for update;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode = '22023'; end if;
  if s.customer_id is not null then
    raise exception 'Surat Pesanan % sudah tertaut ke data pelanggan "%".', s.no_sp,
      (select x.nama from public.customers x where x.id = s.customer_id) using errcode = 'P0001';
  end if;
  select * into c from public.customers where id = p_customer;
  if c.id is null then raise exception 'Pelanggan #% tidak ditemukan.', p_customer using errcode = 'P0002'; end if;
  if c.blacklist then
    raise exception 'Pelanggan "%" masuk daftar hitam — SP tidak ditautkan ke pelanggan daftar hitam.', c.nama
      using errcode = '22023';
  end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));
  v_hp := public.hp_baku(s.telp);
  if not ((char_length(coalesce(v_k, '')) >= 2
           and (public.kunci_nama_pelanggan(c.nama) = v_k
                or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k)))
          or (v_hp is not null and c.hp = v_hp)) then
    raise exception 'Nama/No. HP Surat Pesanan % ("%") tidak cocok dengan pelanggan "%". Bila memang pelanggan itu, ubah '
                    'Kepada SP lewat Minta ubah SP dulu.', s.no_sp, coalesce(s.kepada, ''), c.nama
      using errcode = 'P0001';
  end if;
  if c.sales_rep_id is not null and s.sales_rep_id is not null and c.sales_rep_id <> s.sales_rep_id then
    select nama into v_sales from public.sales_reps where id = c.sales_rep_id;
    raise exception 'Pelanggan "%" dipegang sales %, bukan sales SP ini — bila memang pelanggan yang sama, pindahkan dulu '
                    'pelanggannya ke sales SP di tab Pelanggan.', c.nama, coalesce(v_sales, '#' || c.sales_rep_id)
      using errcode = 'P0001';
  end if;
  if s.po_id is not null then
    select p.customer_id into v_po from public.purchase_orders p where p.id = s.po_id;
    if v_po is not null and v_po <> c.id then
      raise exception 'PO Surat Pesanan % sudah atas nama pelanggan lain — pelanggan SP dan PO harus sama.', s.no_sp
        using errcode = 'P0001';
    end if;
  end if;

  update public.sales_orders set customer_id = c.id, diubah_pada = now(), diubah_oleh = auth.uid() where id = p_so;
  if s.po_id is not null then
    update public.purchase_orders set customer_id = c.id where id = s.po_id and customer_id is null;
  end if;
  if v_ind is not null then
    if c.industri is null then update public.customers set industri = v_ind where id = c.id;   -- yang sudah terisi tidak ditimpa
    else v_pakai := c.industri = v_ind; end if;
  end if;
  return jsonb_build_object('customer_id', c.id, 'dibuat', false, 'dicocokkan', 'pilih', 'kategori_dipakai', v_pakai,
                            'industri', (select x.industri from public.customers x where x.id = c.id), 'nama', c.nama);
end $$;
revoke all on function public.tautkan_pelanggan_sp(bigint, bigint, text) from public, anon;
grant execute on function public.tautkan_pelanggan_sp(bigint, bigint, text) to authenticated;

-- G · uji diri
do $$
begin
  if public.kunci_nama_pelanggan('P.T. Tokai Rubber Indonesia') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan('P T Tokai Rubber Indonesia') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan(E'P​T Tokai Rubber Indonesia') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan(E'Tokai Rubbеr Indonesia, PT') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan('C. V. Maju Jaya T.b.k.') <> 'maju jaya'
     or public.kunci_nama_pelanggan('Toko Maju') <> 'maju'
     or public.kunci_nama_pelanggan(null) <> ''
     or public.rhj_nama_rapi(E'P​T Tokai Rubber') <> 'PT Tokai Rubber'
     or not public.ada_huruf_non_latin(E'Tokai Rubbеr')
     or public.ada_huruf_non_latin('Café Ünal & Söhne, PT (Jkt) 2')
  then
    raise exception '139r: uji kunci nama gagal.';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass and tgname = 'so_a_kepada_bersih') then
    raise exception '139r: trigger so_a_kepada_bersih belum terpasang.';
  end if;
  if position('139r' in pg_get_functiondef('public.customers_tolak_nama_ganda()'::regprocedure)) = 0
     or position('139r' in pg_get_functiondef('public.lengkapi_pelanggan_sp(bigint,text,text,text)'::regprocedure)) = 0
     or position('139r' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0 then
    raise exception '139r: tambalan belum terpasang.';
  end if;
end $$;
