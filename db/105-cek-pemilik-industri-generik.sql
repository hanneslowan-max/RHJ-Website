-- Berkas 105 (#20 #25): perbaikan temuan review kelompok G8-pelanggan.
--
-- (A) #20/#4 cek_pemilik_pelanggan: FE kini (#20) mengirim teks yang sudah dibersihkan tanda bacanya
--     ("PT Indah Kiat Pulp & Paper Tbk" → "indah kiat pulp paper"), sedangkan RPC mencocokkan
--     c.nama ilike '%teks%' utuh → tidak ketemu → peringatan "sudah dipegang sales lain" hilang (regresi #4).
--     Perbaikan: RPC menormalkan KEDUA sisi — huruf kecil, semua non-alfanumerik jadi spasi, kata
--     badan usaha (pt/cv/ud/pd/tb/tbk/toko) dibuang — lalu mencocokkan kata-kata berurutan
--     ('%kata1%kata2%') ke nama kini DAN nama_lama. Kata hanya berisi huruf/angka, jadi % _ \ tidak
--     mungkin ikut (tanpa perlu escape). Minimal 3 huruf setelah dibersihkan. Gerbang, kolom keluaran
--     (nama + nama sales saja), acuan sales, limit 5: tidak berubah. Kompatibel dengan index.html lama.
-- (B) #25 rhj_industri_tebak: kata generik (supplier, trading, distributor, toko, store, shop, service,
--     specialist, equipment, peralatan, maintenance, export/importir/perdagangan, grosir/wholesaler/
--     eceran) tidak lagi dipetakan ke 'Non Otomotif' → NULL (diisi manual). Tambah yang jelas: DAPUR,
--     REFRIGERAT, CARPET/KARPET.
-- (C) DATA DEV: baris yang diisi otomatis oleh berkas 101 dan BELUM disentuh sejak itu
--     (industri = industri_baru dan diubah_pada = dicatat_pada) dihitung ulang dengan peta baru.
--     Nilai sebelum koreksi dicatat di customers_industri_koreksi_105 (RLS aktif, tanpa akses klien).
--     Pulihkan ke hasil 101: update customers c set industri = k.industri_sebelum
--       from customers_industri_koreksi_105 k where k.id = c.id and c.industri is not distinct from k.industri_sesudah;
--     Pulihkan ke sebelum 101 (semua NULL): lihat berkas 101. industri_lama tidak disentuh.
--
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 29 Sep 2026. Belum ke produksi.

-- (A) ─────────────────────────────────────────────────────────────────────────
create or replace function public.cek_pemilik_pelanggan(p_nama text, p_rep bigint default null)
returns table(nama text, sales_nama text)
language plpgsql stable security definer set search_path = public as $$
declare t text := btrim(coalesce(p_nama, '')); v_acuan bigint; v_pola text;
begin
  if not public.boleh_baca() then return; end if;      -- peran lain: kosong, tanpa bocoran
  if char_length(t) < 3 then return; end if;
  -- sales: acuannya selalu dirinya sendiri (p_rep diabaikan); peran lain: sales yang sedang dipilih.
  v_acuan := case when public.peran_saya() = 'sales' then public.sales_rep_saya() else p_rep end;
  -- #20: kata-kata alfanumerik saja, tanpa badan usaha; tanda baca tidak lagi menentukan cocok/tidak.
  select string_agg(k, '%' order by n) into v_pola
    from regexp_split_to_table(btrim(regexp_replace(lower(t), '[^[:alnum:]]+', ' ', 'g')), ' ')
         with ordinality as s(k, n)
   where k <> '' and k not in ('pt','cv','ud','pd','tb','tbk','toko');
  if char_length(replace(coalesce(v_pola, ''), '%', '')) < 3 then return; end if;
  v_pola := '%' || v_pola || '%';
  return query
    select c.nama, sr.nama || case when sr.aktif then '' else ' (nonaktif)' end
      from public.customers c join public.sales_reps sr on sr.id = c.sales_rep_id
     where (regexp_replace(lower(c.nama), '[^[:alnum:]]+', ' ', 'g') like v_pola
            or regexp_replace(lower(coalesce(c.nama_lama, '')), '[^[:alnum:]]+', ' ', 'g') like v_pola)
       and (v_acuan is null or c.sales_rep_id <> v_acuan)
     order by c.nama limit 5;
end $$;
revoke execute on function public.cek_pemilik_pelanggan(text, bigint) from public, anon;
grant  execute on function public.cek_pemilik_pelanggan(text, bigint) to authenticated;

-- (B) ─────────────────────────────────────────────────────────────────────────
create or replace function public.rhj_industri_tebak(p text)
returns text language sql immutable set search_path = public as $$
  with x as (select upper(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))) u)
  select case
    when u = '' then null
    when u ~ '^NON[ -]?OTOMOTIF' then 'Non Otomotif'
    when u ~ '\mBENGKEL\s+(OTOMOTIF|OTOMITIF|MOBIL|MOTOR)\M|\(BENGKEL OTOMOTIF\)'
      then case when u ~ '\m(PABRIK|NON)\M' then null else 'Bengkel Otomotif' end
    when u ~ 'OTOMOTIF|OTOMITIF|AUTOMOTI[FV]|AUTO ?PARTS?\M|AUTO BODY|\mCAR\M|MOTORCAR|\mMOBIL\M|SEPEDA MOTOR|MOTORCYCLE|KENDARAAN|KAROSERI|\mVELG\M|KNALPOT|\mR[24]\M|ASTRA HONDA|\mAHM\M|DAIHATSU|\mHONDA\M|TWO WHEEL|4 WHE+L'
      then 'Otomotif'
    when u ~ '^(PABRIK|BENGKEL\??|COMPANY|JASA|ONLINE|WORKSHOP|MANUFACTURING|INDUSTRI|CORPORATE OFFICE|BRANCH OFFICE.*)$' then null
    when u ~ 'MAKANAN|MINUMAN|\mFOOD|BEVERAGE|BAVERAGE|\mF ?& ?B\M|\mROTI\M|BAKER|BISKUIT|COKELAT|PERMEN|CANDY|ICE CREAM|ES CREAM|\mSUSU\M|\mGULA\M|TEPUNG|BUMBU|PERASA|SOSIS|NUGGET|BAKSO|DAGING|SEAFOOD|PERIKANAN|UNGGAS|\mAYAM\M|TERNAK|PERKEBUNAN|PERTANIAN|CATERING|RESTAURANT|\mCAKE|DONAT|MINYAK KELAPA|INGREDIENT|SEASONING|\mTEH\M|FARMASI|PHARMA|\mOBAT|\mJAMU|KOSMETIK|COSMETI|HOSPITAL|RUMAH SAKIT|ALKES|KESEHATAN|MEDICAL|LABORATOR|HOTEL|RESORT|PERHOTELAN|SUPERMARKET|SWALAYAN|TOSERBA|\mMALL\M|SHOPPING|MINIMARKET|APARTEMEN|CARREFOUR|TEKSTIL|TEXTILE|GARMEN|\mKAIN\M|BENANG|KONVEKSI|SEPATU|SHOES|ALAS KAKI|PERTENUNAN|TENUN|FASHION|FIBERS|SARUNG TANGAN|PEMBALUT|TISSUE|PLASTI[KC]|PALSTIK|KIMIA|CHEMICAL|\mCAT\M|COATING|KERTAS|PAPER|PACKAGING|PACKING|KEMASAN|KARTON|KARUNG|STEROFOAM|SEDOTAN|\mLEM\M|KONTRA[KC]TOR|CONTRA[CK]TOR|KONSTRUKSI|KONTRUKTOR|KOSTRUKSI|CONS?T[RU]*[UR]CTION|BANGUNAN|BUILDING|GYPSUM|KERAMIK|\mKACA\M|GLASS|SEMEN|\mBATA\M|BATAKO|GENTENG|MARMER|SANITA|SCAFFOLDING|CIVIL|SIPIL|INTERIOR|FURNITURE|MEBEL|KITCHEN|\mRAK\M|RACKING|ETALASE|EKSPEDISI|PENGIRIMAN|LOGISTI|\mGUDANG|WAREHOUS|TRANSPORTASI|PENGANGKUTAN|PEGANGKUTAN|COLDSTORAGE|DELIVERY|ELEKTRONI|ELECTRONIC|LISTRIK|SWITCHBOARD|\mKABEL|SOUND SYSTEM|ALAT TULIS|STATIONER|FOTOCOPY|PERCETAKAN|PRINTING|PUBLISHING|PERTAMBANGAN|MINING|\mGAS\M|PERTAMINA|LIMBAH|AIR BERSIH|EDUCATION|KOPERASI|OFFICE SUPPLY|KANTOR|CONSULT|KONSULTA|RUMAH TANGGA|ALAT DAPUR|PANCI|TROLL?E?Y|MATERIAL HANDLING|HANDLING MATERIAL|HANDLING EQUIPMENT|CONVEYOR|PEMINDAH|PENGANGKAT|PERGUDANGAN|\mKAYU\M|ROTAN|BAMBU|WOOD|\mKULIT\M|PANGAN|KASUR|BINGKAI|KARTU|\mSEPEDA\M|\mDAPUR\M|REFRIGERAT|CARPET|KARPET|JAHIT|DEKORA|\mTALI\M|PENGEPAKAN|CLOSET|PISAU'
      then 'Non Otomotif'
    when u ~ 'SPARE ?PARTS?|SPAREPARTS?|\mPARTS?\M|KOMPONEN|COMPONENT|SUKU CADANG|FILTER|\mAKI\M|BATTERY|BATERAI|\mBAN\M|STAMPING|CASTING|FORGING|DIESEL|\mPRESS|\mMESIN\M|MACHINE REPAIR|ALAT BERAT|HEAVY EQUIPMENT|TURBIN'
      then null                                    -- ambigu: bisa otomotif
    -- #25 (105): SUPPLIER/TRADING/DISTRIBUTOR/TOKO/STORE/SHOP/SERVICE/SPECIALIST/EQUIPMENT/PERALATAN/
    --   MAINTENANCE/EXPORT/IMPORTIR/PERDAGANGAN/GROSIR/WHOLESALER/ECERAN sengaja TIDAK dipetakan:
    --   pemasok/toko/distributor bisa saja bergerak di otomotif → NULL, diisi manual (Vonny ditanya).
    when u ~ 'FABRIKASI|FABRI[AC]*CAT|PABRIKASI|MACHINING|MACHINER|MACHINE|ENGINEERING|\mBUBUT|\mLAS\M|WELDING|METAL|LOGAM|\mBAJA\M|STEEL|STAINLES|ALUMUNIUM|ALUMINIUM|\mTOOLS?\M|PERKAKAS|MOULD|MOLD|\mDIES|\mJIG|AUTOMATION|AUTTOMATION|PNEUMATI|HYDRAULIC|POMPA|VALVE|KATUP|BEARING|SPRING|FASTENER|SEKRUP|MECHANICAL|ELECTRICAL|ELECTRIC|KARET|RUBBER|\mPIPA\M|\mTANK\M|\mPANEL\M|PRECISION|PRESISI|\mCNC\M|KOMPRESSOR|GENERATOR|JENSET|\mSEAL\M|CASTER|INDUSTRIAL|KAWAT|PENDINGIN|\mSENG\M'
      then 'Non Otomotif'
    else null end
  from x
$$;

revoke execute on function public.rhj_industri_tebak(text) from public, anon;
grant execute on function public.rhj_industri_tebak(text) to authenticated, service_role;

-- (C) DATA DEV ────────────────────────────────────────────────────────────────
create table if not exists public.customers_industri_koreksi_105 (
  id bigint primary key, industri_lama text, industri_sebelum text, industri_sesudah text,
  dicatat_pada timestamptz not null default now());
alter table public.customers_industri_koreksi_105 enable row level security;
revoke all on public.customers_industri_koreksi_105 from anon, authenticated;
insert into public.customers_industri_koreksi_105 (id, industri_lama, industri_sebelum, industri_sesudah)
select c.id, c.industri_lama, c.industri, public.rhj_industri_tebak(c.industri_lama)
  from public.customers c join public.customers_industri_sebelum_101 b on b.id = c.id
 where c.industri = b.industri_baru and c.diubah_pada = b.dicatat_pada
   and public.rhj_industri_tebak(c.industri_lama) is distinct from c.industri
on conflict (id) do nothing;
update public.customers c set industri = k.industri_sesudah
  from public.customers_industri_koreksi_105 k
 where k.id = c.id and c.industri is not distinct from k.industri_sebelum;
