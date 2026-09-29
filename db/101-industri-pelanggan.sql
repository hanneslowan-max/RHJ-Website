-- Berkas 101 (#25): kategori industri pelanggan (Otomotif / Non Otomotif / Bengkel Otomotif).
--
-- Temuan: 5.394 dari 5.395 pelanggan DEV industri NULL; teks lama sheet ada di industri_lama
--   (1.761 terisi, 835 nilai unik). FE Vonny (formCekVonny, formKirim) mengisi kategori lewat
--   PATCH /customers {industri}, tetapi RLS cust_ubah memakai boleh_ubah_crm() (owner/gm/staff/sales),
--   sehingga untuk Vonny 0 baris berubah tanpa galat → isian Vonny TIDAK PERNAH tersimpan.
--
-- (1) rhj_industri_tebak(text): peta KONSERVATIF teks industri_lama → kategori. Hanya yang jelas:
--     "bengkel otomotif/mobil/motor" → Bengkel Otomotif; otomotif/automotive/karoseri/mobil/motor/…
--     → Otomotif; industri non-otomotif yang jelas (makanan, farmasi, hotel, ritel, tekstil, plastik,
--     kimia, konstruksi, logistik, elektronik, troli/material handling, …) → Non Otomotif; lalu kata
--     ambigu (spare part, komponen, mesin, ban, aki, press, casting, alat berat, …) → NULL; lalu
--     fabrikasi/logam/supplier/trading/toko → Non Otomotif. Sisanya NULL (diisi manual).
-- (2) RPC set_industri_pelanggan(p_customer, p_industri): SECURITY DEFINER. Boleh untuk owner/gm/vonny
--     (boleh_konfirmasi_kirim) atau peran CRM (owner/gm/staff/sales; sales hanya pelanggan miliknya /
--     belum bertuan). Nilai hanya tiga kategori (22023). FE Vonny memakai RPC ini.
--     RLS customers TIDAK diubah (Vonny tetap tidak bisa PATCH kolom lain).
-- (3) DATA DEV: cadangan ke customers_industri_sebelum_101 (RLS aktif, tanpa akses anon/authenticated),
--     lalu isi HANYA baris industri NULL yang petanya jelas. industri_lama tidak disentuh.
--     Pulihkan: update customers c set industri = null from customers_industri_sebelum_101 b
--               where b.id = c.id and c.industri = b.industri_baru;
--
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 29 Sep 2026. Belum ke produksi.

-- (1) ─────────────────────────────────────────────────────────────────────────
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
    when u ~ 'MAKANAN|MINUMAN|\mFOOD|BEVERAGE|BAVERAGE|\mF ?& ?B\M|\mROTI\M|BAKER|BISKUIT|COKELAT|PERMEN|CANDY|ICE CREAM|ES CREAM|\mSUSU\M|\mGULA\M|TEPUNG|BUMBU|PERASA|SOSIS|NUGGET|BAKSO|DAGING|SEAFOOD|PERIKANAN|UNGGAS|\mAYAM\M|TERNAK|PERKEBUNAN|PERTANIAN|CATERING|RESTAURANT|\mCAKE|DONAT|MINYAK KELAPA|INGREDIENT|SEASONING|\mTEH\M|FARMASI|PHARMA|\mOBAT|\mJAMU|KOSMETIK|COSMETI|HOSPITAL|RUMAH SAKIT|ALKES|KESEHATAN|MEDICAL|LABORATOR|HOTEL|RESORT|PERHOTELAN|SUPERMARKET|SWALAYAN|TOSERBA|\mMALL\M|SHOPPING|GROSIR|MINIMARKET|APARTEMEN|WHOLESALER|ECERAN|CARREFOUR|TEKSTIL|TEXTILE|GARMEN|\mKAIN\M|BENANG|KONVEKSI|SEPATU|SHOES|ALAS KAKI|PERTENUNAN|TENUN|FASHION|FIBERS|SARUNG TANGAN|PEMBALUT|TISSUE|PLASTI[KC]|PALSTIK|KIMIA|CHEMICAL|\mCAT\M|COATING|KERTAS|PAPER|PACKAGING|PACKING|KEMASAN|KARTON|KARUNG|STEROFOAM|SEDOTAN|\mLEM\M|KONTRA[KC]TOR|CONTRA[CK]TOR|KONSTRUKSI|KONTRUKTOR|KOSTRUKSI|CONS?T[RU]*[UR]CTION|BANGUNAN|BUILDING|GYPSUM|KERAMIK|\mKACA\M|GLASS|SEMEN|\mBATA\M|BATAKO|GENTENG|MARMER|SANITA|SCAFFOLDING|CIVIL|SIPIL|INTERIOR|FURNITURE|MEBEL|KITCHEN|\mRAK\M|RACKING|ETALASE|EKSPEDISI|PENGIRIMAN|LOGISTI|\mGUDANG|WAREHOUS|TRANSPORTASI|PENGANGKUTAN|PEGANGKUTAN|COLDSTORAGE|DELIVERY|ELEKTRONI|ELECTRONIC|LISTRIK|SWITCHBOARD|\mKABEL|SOUND SYSTEM|ALAT TULIS|STATIONER|FOTOCOPY|PERCETAKAN|PRINTING|PUBLISHING|PERTAMBANGAN|MINING|\mGAS\M|PERTAMINA|LIMBAH|AIR BERSIH|EDUCATION|KOPERASI|OFFICE SUPPLY|KANTOR|CONSULT|KONSULTA|RUMAH TANGGA|ALAT DAPUR|PANCI|TROLL?E?Y|MATERIAL HANDLING|HANDLING MATERIAL|HANDLING EQUIPMENT|CONVEYOR|PEMINDAH|PENGANGKAT|PERGUDANGAN|\mKAYU\M|ROTAN|BAMBU|WOOD|\mKULIT\M|PANGAN|KASUR|BINGKAI|KARTU|\mSEPEDA\M|JAHIT|DEKORA|\mTALI\M|PENGEPAKAN|CLOSET|PISAU'
      then 'Non Otomotif'
    when u ~ 'SPARE ?PARTS?|SPAREPARTS?|\mPARTS?\M|KOMPONEN|COMPONENT|SUKU CADANG|FILTER|\mAKI\M|BATTERY|BATERAI|\mBAN\M|STAMPING|CASTING|FORGING|DIESEL|\mPRESS|\mMESIN\M|MACHINE REPAIR|ALAT BERAT|HEAVY EQUIPMENT|TURBIN'
      then null                                    -- ambigu: bisa otomotif
    when u ~ 'FABRIKASI|FABRI[AC]*CAT|PABRIKASI|MACHINING|MACHINER|MACHINE|ENGINEERING|\mBUBUT|\mLAS\M|WELDING|METAL|LOGAM|\mBAJA\M|STEEL|STAINLES|ALUMUNIUM|ALUMINIUM|\mTOOLS?\M|PERKAKAS|MOULD|MOLD|\mDIES|\mJIG|AUTOMATION|AUTTOMATION|PNEUMATI|HYDRAULIC|POMPA|VALVE|KATUP|BEARING|SPRING|FASTENER|SEKRUP|SUPP?I?LIER|SUPPILER|SUPPLY|SUPPLIES|TRADING|TRADE\M|DISTRIBUT|IMPORTIR|EXPORT|PERDAGANGAN|\mTOKO\M|STORE|\mSHOP\M|MECHANICAL|ELECTRICAL|ELECTRIC|MAINTENANCE|MAINTEBANCE|EQUIPMENT|PERALATAN|KARET|RUBBER|\mPIPA\M|\mTANK\M|\mPANEL\M|PRECISION|PRESISI|\mCNC\M|KOMPRESSOR|GENERATOR|JENSET|\mSEAL\M|CASTER|SPECIALIST|\mSERVICE|INDUSTRIAL|KAWAT|PENDINGIN|\mSENG\M'
      then 'Non Otomotif'
    else null end
  from x
$$;

-- (2) ─────────────────────────────────────────────────────────────────────────
create or replace function public.set_industri_pelanggan(p_customer bigint, p_industri text)
returns text language plpgsql security definer set search_path = public as $$
declare v text := nullif(btrim(p_industri), ''); c public.customers;
begin
  if v is null or v not in ('Otomotif','Non Otomotif','Bengkel Otomotif') then
    raise exception 'Kategori industri hanya Otomotif, Non Otomotif, atau Bengkel Otomotif.' using errcode='22023';
  end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'Pelanggan tidak ditemukan.' using errcode='P0002'; end if;
  if not (public.boleh_konfirmasi_kirim()
          or (public.boleh_ubah_crm() and (public.peran_saya() <> 'sales'
              or c.sales_rep_id is null or c.sales_rep_id = public.sales_rep_saya()))) then
    raise exception 'Anda tidak berwenang mengubah kategori pelanggan ini.' using errcode='42501';
  end if;
  update public.customers set industri = v where id = p_customer;
  return v;
end $$;
revoke execute on function public.set_industri_pelanggan(bigint, text), public.rhj_industri_tebak(text) from public, anon;
grant execute on function public.set_industri_pelanggan(bigint, text), public.rhj_industri_tebak(text) to authenticated, service_role;

-- (3) DATA DEV ────────────────────────────────────────────────────────────────
create table if not exists public.customers_industri_sebelum_101 (
  id bigint primary key, industri text, industri_lama text, industri_baru text not null,
  diubah_oleh uuid, diubah_pada timestamptz, dicatat_pada timestamptz not null default now());
alter table public.customers_industri_sebelum_101 enable row level security;
revoke all on public.customers_industri_sebelum_101 from anon, authenticated;
insert into public.customers_industri_sebelum_101 (id, industri, industri_lama, industri_baru, diubah_oleh, diubah_pada)
select id, industri, industri_lama, public.rhj_industri_tebak(industri_lama), diubah_oleh, diubah_pada
  from public.customers where industri is null and public.rhj_industri_tebak(industri_lama) is not null
on conflict (id) do nothing;
update public.customers c set industri = b.industri_baru
  from public.customers_industri_sebelum_101 b where b.id = c.id and c.industri is null;
