-- ═══════════════════════════════════════════════════════════════════════
-- 139w · Tindak lanjut review berkas 139r (temuan keamanan #2: nama & pemegang pelanggan)
-- (nomor 139w: jatah nomor sesi ini 120–139; "w" diurutkan sesudah 139v dan sebelum berkas EHC 140+.
--  Jalankan sesudah 138, 139, dan 139r.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  1/8. (sedang) Huruf mirip di blok huruf Latin sendiri — ǀ (U+01C0, garis tegak = "I" di font sans), ı (i tanpa
--     titik), ĸ, ȷ, Ɩ, İ — tidak ditolak ada_huruf_non_latin (yang menerima seluruh À-ɏ) dan tidak dilipat kunci.
--     Sales membuat "PT Tokai Rubber ǀndonesia" di samping pelanggan sales lain dan cek Vonny menyatakannya pelanggan
--     baru. → huruf yang diterima dipersempit ke A–Z, angka, dan huruf beraksen umum (Latin-1, Latin Extended-A tanpa
--     ı ĸ ŀ ŉ ſ İ, Vietnam); sisanya ditolak (P0001) untuk selain owner/GM/staff — juga Kepada SP. Kunci melipat
--     ı ȷ ĸ dan membuang tanda gabung tak berpasangan (mis. i + titik atas U+0307 yang tak terlihat).
--  2. (rendah) Bentuk badan usaha berhuruf tunggal dibuang di mana pun, jadi inisial orang "Bp. T.B. Silalahi" =
--     "Bp Silalahi" (SP ditautkan ke orang lain, 8a menolak nama sah). → "p t · c v · u d · p d · t b" hanya dibuang di
--     AWAL atau AKHIR nama (posisi badan usaha); "t b k" tetap di mana pun.
--  3. (rendah) NFKC mengubah teks yang disimpan/dicetak: Kepada "1½ Inch" → "11⁄2 Inch", "PT ABC™" → "PT ABCTM".
--     → teks_tanpa_format kini NFC + karakter format dibuang (untuk nama & Kepada yang disimpan); NFKC hanya di kunci
--     (kunci tidak pernah ditampilkan). Huruf lebar penuh/huruf matematika kini ditolak untuk selain owner/GM/staff
--     (dulu dilipat diam-diam); kuncinya tetap sama dengan huruf biasa.
--  4. (rendah) Tindakan "hp_sales_lain" menyarankan "Tautkan ke pelanggan tertentu" — jalan buntu (No. HP unik,
--     kandidat kosong) — dan pesan lengkapi kasus No. HP menyuruh mengubah Kepada. → saran diperbaiki per kasus.
--  9. (rendah) urutan rilis `sort -V` menaruh 139r sebelum 139 → 139r berhenti di jangkar. → skill rilis diurutkan
--     `sort -t- -k1,1V`; 139r & 139s diberi pemeriksaan prasyarat di awal berkas.
--  Di index.html: 5 (regex ES2018 dibangun saat jalan), 6 (Kepada non-Latin diperiksa sebelum nomor SP diambil),
--  7 (toast kategori sesudah "Tautkan ke ini"), cermin kunci & huruf yang diterima. 10 (cek PROD) → HANDOFF.
-- Tambalan definisi hidup memakai pemeriksaan jangkar. Tidak ada data yang diubah (indeks kunci nama dibangun ulang;
-- DEV: tidak ada kunci yang berubah); tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139y: menjalankannya ulang sendirian menurunkan fungsi yang diperbarui berkas sesudahnya
--      (review 139v no. 2). Untuk mundur: cadangan definisi fungsi
--      sebelum rilis (skill cto-rilis-prod). rhj.ulang_rantai = 'on' melewati penjaga — darurat saja.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '139w: berkas ini sudah disusul 139y — jangan dijalankan ulang sendirian. '
                    'Untuk mundur pakai cadangan definisi fungsi yang disimpan sebelum rilis (skill cto-rilis-prod).';
  end if;
end $$;

do $$ begin
  if to_regprocedure('public.teks_tanpa_format(text)') is null
     or position('v_milik' in pg_get_functiondef('public.lengkapi_pelanggan_sp(bigint,text,text,text)'::regprocedure)) = 0 then
    raise exception '139w: jalankan 138, 139, dan 139r dulu.';
  end if;
end $$;

-- A · teks yang disimpan: NFC + karakter format (tak terlihat) dibuang — soft hyphen, zero-width, penanda arah, word
--     joiner, variation selector, BOM, pengisi Hangul, karakter tag. Bentuk kompatibilitas (½ ™ ²) tidak diubah.
create or replace function public.teks_tanpa_format(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select normalize(regexp_replace(p,
    '[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ\U000e0000-\U000e0fff]',
    '', 'g'), NFC)
$$;
comment on function public.teks_tanpa_format(text) is '139w: NFC + karakter format (tak terlihat) dibuang (NFKC hanya di kunci).';

-- huruf/angka yang diterima untuk selain owner/GM/staff: 0-9, A-Z, ª º, Latin-1 beraksen, Latin Extended-A tanpa
-- ı (0131) İ (0130) ĸ (0138) Ŀŀ (013F/0140) ŉ (0149) ſ (017F), Latin Extended Additional (Vietnam dsb.) tanpa
-- 1E96–1E9F & 1EFA–1EFF. Di luar itu (Kiril, Yunani, Latin Extended-B seperti ǀ Ɩ, huruf lebar penuh, µ) → true.
create or replace function public.ada_huruf_non_latin(p text)
returns boolean language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(regexp_replace(coalesce(public.teks_tanpa_format(p), ''), '[^[:alnum:]]', '', 'g'),
           '[0-9A-Za-zªºÀ-ÖØ-öø-įĲ-ķĹ-ľŁ-ňŊ-žḀ-ẕẠ-ỹ]',
           '', 'g') <> ''
$$;
comment on function public.ada_huruf_non_latin(text) is
  '139w: true bila ada huruf/angka di luar A-Z, angka, dan huruf beraksen umum (mis. Kiril/Yunani, ǀ ı ĸ).';

-- B · kunci nama: NFKC, huruf mirip dipetakan (Kiril/Yunani + ı ȷ ĸ), tanda gabung dibuang, badan usaha berhuruf
--     tunggal hanya di awal/akhir (t b k di mana pun), kata badan usaha dibuang
create or replace function public.kunci_nama_pelanggan(p text)
returns text language sql immutable set search_path = public as $$
  select coalesce(string_agg(k, ' ' order by n), '')
    from regexp_split_to_table(
           btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
             ' ' || regexp_replace(
                      translate(regexp_replace(lower(normalize(coalesce(public.teks_tanpa_format(p), ''), NFKC)),
                                               '[̀-ͯ᪰-᫿᷀-᷿⃐-⃿︠-︯]', '', 'g'),
                                'аеорсухіјѕкмнтвӏԁԛԝαβεζηικμνορτυχıȷĸ', 'aeopcyxijskmhtbldqwabezhikmnoptyxijk'),
                      '[^[:alnum:]]+', ' ', 'g') || ' ',
             ' t b k(?= )', ' ', 'g'),
             '^ +(p t|c v|u d|p d|t b) ', ' '),
             ' (p t|c v|u d|p d|t b) +$', ' '),
           ' +', ' ', 'g')), ' ')
         with ordinality as s(k, n)
   where k <> '' and k not in ('pt','cv','ud','pd','tb','tbk','toko')
$$;
reindex index public.customers_kunci_nama_idx;
reindex index public.customers_kunci_nama_lama_idx;

-- C · tambalan definisi hidup (jangkar harus muncul tepat n kali; dilewati bila tambalannya sudah ada)
do $$
declare
  t text[];
  d text; d2 text; n int;
  daftar text[] := array[
    -- (no. 4) cek_kelayakan_vonny: hp_sales_lain — tanpa saran "Tautkan ke pelanggan tertentu" (No. HP unik → buntu)
    ['public.cek_kelayakan_vonny(bigint,text,text)',
     $a$'Periksa nomornya dulu — bila salah ketik, perbaiki No. HP di laci cek. Bila memang pelanggan '$a$,
     $b$'Periksa nomornya dulu — bila salah ketik atau bukan nomor pelanggan ini, perbaiki No. HP di laci cek (atau Minta ubah SP). Bila memang pelanggan '$b$, '1'],
    ['public.cek_kelayakan_vonny(bigint,text,text)',
     $a$' (tab Pelanggan), atau menautkan SP ini ke pelanggan lain yang benar (Tautkan ke pelanggan '
                   || 'tertentu — laci cek atau detail SP).';$a$,
     $b$' (tab Pelanggan).';   -- 139w: tanpa "Tautkan ke pelanggan tertentu" (No. HP unik, kandidat kosong)$b$, '1'],
    -- (no. 4) lengkapi_pelanggan_sp: saran per kasus — No. HP → perbaiki No. HP; nama → beri pembeda pada Kepada
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)',
     $a$'lain, ubah Kepada lewat Minta ubah SP (beri pembeda, mis. kota/cabang).',
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id)$a$,
     $b$'lain, %',   -- 139w: saran per kasus
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id),
                      case v_cocok when 'hp' then 'perbaiki No. HP SP (laci cek / Minta ubah SP) — No. HP satu pelanggan '
                                                  || 'tidak bisa dipakai pelanggan lain.'
                                   else 'ubah Kepada lewat Minta ubah SP (beri pembeda, mis. kota/cabang).' end$b$, '1']
  ];
begin
  foreach t slice 1 in array daftar loop
    d := pg_get_functiondef(t[1]::regprocedure);
    if position(t[3] in d) > 0 then continue; end if;   -- sudah ditambal
    n := (length(d) - length(replace(d, t[2], ''))) / length(t[2]);
    if n <> t[4]::int then
      raise exception '139w: % — jangkar "%" muncul % kali (harus %).', t[1], left(t[2], 70), n, t[4];
    end if;
    execute replace(d, t[2], t[3]);
    d2 := pg_get_functiondef(t[1]::regprocedure);
    if replace(d2, t[3], t[2]) <> d then raise exception '139w: % — hasil tambalan tidak sesuai.', t[1]; end if;
  end loop;
end $$;

-- D · uji diri
do $$
begin
  if public.kunci_nama_pelanggan('P.T. Tokai Rubber Indonesia') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan('P T Tokai Rubber Indonesia') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan('P' || chr(8203) || 'T Tokai Rubber Indonesia') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan('Tokai Rubb' || chr(1077) || 'r Indonesia, PT') <> 'tokai rubber indonesia'   -- е Kiril
     or public.kunci_nama_pelanggan('Tokai Rubber Indonesi' || chr(775) || 'a') <> 'tokai rubber indonesia'      -- i + titik atas
     or public.kunci_nama_pelanggan('Toka' || chr(305) || ' Rubber Indonesia') <> 'tokai rubber indonesia'        -- ı
     or public.kunci_nama_pelanggan('Tokai Rubber Indonesia, P.T.') <> 'tokai rubber indonesia'
     or public.kunci_nama_pelanggan('C. V. Maju Jaya T.b.k.') <> 'maju jaya'
     or public.kunci_nama_pelanggan('Bp. T.B. Silalahi') = public.kunci_nama_pelanggan('Bp Silalahi')
     or public.kunci_nama_pelanggan('Klinik dr. P. D. Hutapea') = public.kunci_nama_pelanggan('Klinik dr. Hutapea')
     or public.kunci_nama_pelanggan('PT ABC' || chr(8482)) <> public.kunci_nama_pelanggan('PT ABCTM')            -- ™
     or public.kunci_nama_pelanggan(chr(65328) || chr(65332) || ' Maju') <> 'maju'                                -- ＰＴ lebar penuh
     or public.kunci_nama_pelanggan('Toko Maju') <> 'maju'
     or public.kunci_nama_pelanggan(null) <> ''
     or public.teks_tanpa_format('Toko Besi 1' || chr(189) || ' Inch') <> 'Toko Besi 1' || chr(189) || ' Inch'    -- ½ utuh
     or position(chr(8482) in public.rhj_nama_rapi('PT ABC' || chr(8482) || ' Indonesia')) = 0
     or public.rhj_nama_rapi('P' || chr(8203) || 'T Tokai Rubber') <> 'PT Tokai Rubber'
     or public.teks_tanpa_format('e' || chr(8205) || chr(769)) <> chr(233)                                        -- e+ZWJ+akut → é
  then
    raise exception '139w: uji kunci/teks nama gagal.';
  end if;
  if not (public.ada_huruf_non_latin('Tokai Rubb' || chr(1077) || 'r')        -- Kiril
          and public.ada_huruf_non_latin('Rubber ' || chr(448) || 'ndonesia')  -- ǀ
          and public.ada_huruf_non_latin('Toka' || chr(305))                   -- ı
          and public.ada_huruf_non_latin('To' || chr(312) || 'ai')             -- ĸ
          and public.ada_huruf_non_latin(chr(304) || 'ndonesia')              -- İ
          and public.ada_huruf_non_latin(chr(406) || 'ndonesia')              -- Ɩ
          and public.ada_huruf_non_latin(chr(65328) || chr(65332) || ' X')    -- lebar penuh
          and public.ada_huruf_non_latin('Toko ' || chr(26481) || chr(26041)))  -- 東方
     or public.ada_huruf_non_latin('Café Ünal & Söhne, PT (Jkt) 2')
     or public.ada_huruf_non_latin('Nguy' || chr(7877) || 'n ' || chr(321) || 'ód' || chr(378))   -- Nguyễn Łódź
     or public.ada_huruf_non_latin('Toko Besi 1' || chr(189) || ' Inch')
     or public.ada_huruf_non_latin('Ma''ruf ' || chr(8217) || 's')
  then
    raise exception '139w: uji huruf yang diterima gagal.';
  end if;
  if position('139w' in pg_get_functiondef('public.lengkapi_pelanggan_sp(bigint,text,text,text)'::regprocedure)) = 0
     or position('139w' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0 then
    raise exception '139w: tambalan belum terpasang.';
  end if;
end $$;
