-- Berkas 100 (#20, lanjutan berkas 71): nama pelanggan rapi v2 + normalisasi otomatis saat simpan.
--
-- Masalah fungsi lama (berkas 71): isi kurung tidak ditangani ("3D ENGINEERING, PT (PT EKA…)"),
--   kurung bisa rusak ("… (KREASI CIPTA UTAMA, PT)" → tutup kurung hilang), "A, CV / PT" salah,
--   singkatan ikut di-initcap ("PT Rpx", "Group Id", "PT Pln"), Tbk/UD/Toko tidak dipindah.
--
-- Fungsi (semua immutable, murni, search_path = public):
--   rhj_nama_segmen(text)         : pindah badan usaha dalam satu segmen tanpa kurung —
--                                   PT/CV/UD/PD/TB/FA/Toko ke depan, Tbk ke belakang,
--                                   "A, PT / B, PT" → "PT A / PT B".
--   rhj_nama_huruf(text, boolean) : huruf besar-kecil per kata. Singkatan dipertahankan lewat
--                                   (a) daftar tetap, (b) kata ≥2 huruf tanpa vokal AIUEOY (RPX, PLN),
--                                   (c) penulisan disengaja: bila >1/3 kata (≥3 huruf) di nama asli
--                                   berhuruf kecil, kata kapital penuh dibiarkan. Kata sambung kecil,
--                                   angka Romawi & kata berangka kapital (3D, UP3).
--   rhj_nama_rapi(text)           : fungsi utama (tanda tangan sama dengan berkas 71). Rapikan spasi &
--                                   tanda baca, segmen tingkat atas + tiap (...), lalu huruf.
--                                   "(tanpa nama)" dibiarkan.
--   rhj_nama_sidik(text)          : sidik huruf (huruf/angka terurut, tanpa tanda baca, huruf kecil);
--                                   sama ⇔ hanya urutan/besar-kecil/tanda baca yang beda.
--   customers_rapi_nama()         : trigger BEFORE INSERT / UPDATE OF nama, nama_lama.
--     - INSERT: nama dirapikan, nama_lama = ketikan asli bila berbeda (kiriman nama_lama klien diabaikan).
--     - UPDATE: nama_lama dikunci (= nilai lama; tak bisa diubah/dihapus lewat REST). Nama berubah →
--       dirapikan, nama_lama diisi ketikan asli hanya bila masih kosong (cadangan sekali saja).
--     - Jalur admin (terapkan/pulihkan/migrasi) menyalakan GUC rhj.lewati_rapi_nama = 'on' (lokal
--       transaksi); klien REST tidak bisa men-set GUC ini.
--   Urutan trigger (alfabetis): jaga_sales, jejak, rapi_nama, sales_bawaan — kolom tidak bertabrakan.
--   terapkan_rapi_nama / pulihkan_nama_pelanggan: tanda tangan & tipe kembali tetap (FE lama jalan).
--     Pulihkan hanya baris yang sidik nama kini = sidik nama_lama (ganti nama manual tidak ditimpa).
--   Kolom baru customers.nama_urut (generated, aditif): nama tanpa awalan PT/CV/UD/PD/TB/FA/Toko/RS,
--     huruf kecil → urutan A→Z tidak menumpuk di huruf P/C.
--
-- Hak akses: rhj_nama_* dicabut dari public/anon, diberikan ke authenticated & service_role.
--
-- DATA DEV (keputusan Hannes: rapikan langsung): cadangan lengkap ke customers_nama_sebelum_100
--   (RLS aktif, tanpa akses anon/authenticated) + terapkan lewat jalur bypass sehingga nama_lama
--   berisi nama asli. customers_jejak mengisi diubah_oleh = NULL, diubah_pada = now(); nilai lama
--   keduanya ada di tabel cadangan. Pelanggan TIDAK digabung walau namanya jadi kembar.
--   Pemulihan total bila perlu:
--     do $$ begin perform set_config('rhj.lewati_rapi_nama','on',true);
--       update customers c set nama=b.nama, nama_lama=b.nama_lama from customers_nama_sebelum_100 b
--        where b.id=c.id and rhj_nama_sidik(c.nama)=rhj_nama_sidik(b.nama); end $$;
--   atau tombol FE "Pulihkan nama asli".
--
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 29 Sep 2026. Belum ke produksi (PROD belum punya berkas 71;
--   urutan kelak 71 → 100 → 101, bagian DATA dipratinjau ulang dengan data PROD).

-- 1) pindah badan usaha dalam satu segmen (tanpa kurung) ─────────────────────
create or replace function public.rhj_nama_segmen(p text)
returns text language plpgsql immutable set search_path = public as $$
declare
  s text := btrim(coalesce(p, ''));
  m text[]; ent text := null; ekor text := ''; tbk boolean := false;
begin
  if s = '' then return s; end if;
  -- akhiran "X, PT" / "X. PT" / "X,PT." (+ ekor "(..)", "/ ..", "& ..")
  m := regexp_match(s, '^(.*?[[:alnum:]).])\s*[,.]\s*(P\.?T|C\.?V|U\.?D|P\.?D|T\.?B|FA|TOKO)\.?((\s*[(/&].*)?)$', 'i');
  if m is null then  -- tanpa koma "X PT" (hanya PT/CV/UD/PD)
    m := regexp_match(s, '^(.*?[[:alnum:])])\s+(P\.?T|C\.?V|U\.?D|P\.?D)\.?((\s*[(/&].*)?)$', 'i');
  end if;
  if m is not null then s := btrim(m[1]); ent := m[2]; ekor := btrim(coalesce(m[3], '')); end if;
  -- awalan "PT X" / "PT. X" / "PT.X" / "CV, X" / "RS. X"
  m := regexp_match(s, '^(P\.?T|C\.?V|U\.?D|P\.?D|T\.?B|FA|TOKO|R\.?S)(?:[.,]|\s)+(.+)$', 'i');
  if m is not null then
    if ent is null then ent := m[1]; s := btrim(m[2]);
    elsif upper(replace(m[1], '.', '')) = upper(replace(ent, '.', '')) then s := btrim(m[2]); -- "PT X, PT"
    end if;
  end if;
  -- Tbk selalu di belakang ("X TBK", "X, Tbk.", "X (TBK)")
  m := regexp_match(s, '^(.*?)[\s,.]*(?:\(\s*TBK\.?\s*\)|\mTBK\M\.?)$', 'i');
  if m is not null and btrim(m[1]) <> '' then s := btrim(m[1]); tbk := true; end if;
  s := btrim(s, ' ,;.-');
  if ekor <> '' and left(ekor, 1) in ('/', '&') then
    ekor := left(ekor, 1) || ' ' || public.rhj_nama_segmen(substr(ekor, 2));
  end if;
  if ent is not null then
    ent := upper(replace(ent, '.', ''));
    if ent = 'TOKO' then ent := 'Toko'; end if;
  end if;
  return btrim(concat_ws(' ', ent, nullif(s, ''), case when tbk then 'Tbk' end, nullif(ekor, '')));
end $$;

-- 2) huruf besar-kecil per kata ──────────────────────────────────────────────
create or replace function public.rhj_nama_huruf(p text, p_campur boolean)
returns text language plpgsql immutable set search_path = public as $$
declare
  r record; hasil text := ''; u text; k text; awal boolean;
  atas constant text[] := array['PT','CV','UD','PD','TB','FA','RS'];
  judul constant text[] := array['TBK','LTD','MFG','PTE','INTL','HJ','DR','JL','ST','MR','MRS','BPK','SDR','DLL','YTH'];
  singkatan constant text[] := array['ID','IT','AC','AE','AT','AB','OB','IK','AI','JO','KSO',
    'YKK','YKT','YTK','IRC','APM','ACS','ADM','AEC','AMK','ANM','ABB','BASF','BKI','BKU','CBA','CKBI',
    'DIC','EDS','GSI','HGI','IAS','IASS','IBS','ICC','IGP','IMIP','ITP','JFE','JTU','KBU','KITM','MEP',
    'MGI','MKI','MPSA','MTU','NSSI','NYH','OPP','OSCT','PPLI','RSI','SBY','SMAP','ZJA','AHM','ADR',
    'BCA','BNI','BRI','BTN','BUMN','OKI','TIKI','WIKA','VIP','JNE','UPS','KAI','IKEA','AEON','NOK','TOA',
    'SMA','SMK','SMAK','UI','ITB','IPB','UGM','ITS','PDAM','LIPI','ABC'];
  romawi constant text[] := array['II','III','IV','VI','VII','VIII','IX','XI','XII','XIII','XIV','XV','XX'];
  sambung constant text[] := array['DAN','AND','OF','THE','DENGAN','UNTUK','DARI','ATAU','YANG'];
  ranah constant text[] := array['COM','NET','ORG'];
begin
  for r in select m[1] sep, m[2] kata from regexp_matches(p, '([^[:alnum:]]*)([[:alnum:]]+)', 'g') m loop
    u := upper(r.kata);
    awal := hasil = '' or r.sep ~ '[(/,&-]';
    k := case
      when r.kata ~ '[0-9]' then
        case when r.kata ~ '^[0-9]+[[:alpha:]]{4,}$'
             then substring(r.kata from '^[0-9]+') || upper(left(substring(r.kata from '[[:alpha:]]+$'),1))
                  || lower(substr(substring(r.kata from '[[:alpha:]]+$'),2))
             else u end
      when r.sep ~ '\.$' and u = any (ranah) then lower(r.kata)
      when u = any (atas) then u
      when u = any (judul) then upper(left(u,1)) || lower(substr(u,2))
      when u = any (singkatan) then u
      when p_campur and r.kata = u and length(r.kata) >= 2 then r.kata
      when p_campur and r.kata ~ '^.+[[:upper:]]' and r.kata ~ '[[:lower:]]' then r.kata
      when r.kata ~ '^[[:alpha:]]{2,}$' and u !~ '[AEIOUY]' then u
      when u = any (romawi) then u
      when not awal and u = any (sambung) then lower(r.kata)
      else upper(left(r.kata,1)) || lower(substr(r.kata,2))
    end;
    hasil := hasil || r.sep || k;
  end loop;
  return hasil || coalesce(substring(p from '[^[:alnum:]]*$'), '');
end $$;

-- 3) fungsi utama (ganti isi, tanda tangan sama) ────────────────────────────
create or replace function public.rhj_nama_rapi(p text)
returns text language plpgsql immutable set search_path = public as $$
declare s text; hasil text := ''; sisa text; m text[]; n_kecil int; n_total int; campur boolean;
begin
  if p is null then return null; end if;
  s := btrim(regexp_replace(p, '[[:space:] ]+', ' ', 'g'));
  if s = '' then return p; end if;
  if lower(s) = '(tanpa nama)' then return '(tanpa nama)'; end if;
  -- "penulisan disengaja": > 1/3 kata (≥3 huruf) berhuruf kecil → kata kapital penuh dipertahankan
  select count(*) filter (where x ~ '[[:lower:]]'), count(*) into n_kecil, n_total
    from (select t[1] x from regexp_matches(s, '[[:alpha:]]{3,}', 'g') t) z
   where upper(x) <> all (array['TBK','LTD','MFG','PTE','INTL','TOKO','PERSERO']);
  campur := n_kecil * 3 > n_total;
  s := regexp_replace(s, '\s*,[\s,]*', ', ', 'g');
  s := regexp_replace(s, '\(\s+', '(', 'g');
  s := regexp_replace(s, '\s+\)', ')', 'g');
  s := regexp_replace(s, '([^\s(/&-])\(', '\1 (', 'g');
  s := regexp_replace(s, '\)([[:alnum:]])', ') \1', 'g');
  s := regexp_replace(s, '\m[Pp]\.\s?[Tt]\.?(\s|$)', 'PT\1', 'g');
  s := regexp_replace(s, '\m[Cc]\.\s?[Vv]\.?(\s|$)', 'CV\1', 'g');
  s := regexp_replace(s, '\m[Uu]\.\s?[Dd]\.?(\s|$)', 'UD\1', 'g');
  s := regexp_replace(s, '\m(PT|CV|UD|PD|TB|RS)\.(\s|$)', '\1\2', 'gi');
  s := btrim(s, ' ,;-');
  s := public.rhj_nama_segmen(s);
  sisa := s;                                   -- badan usaha di dalam tiap (...)
  while sisa ~ '\([^()]*\)' loop
    m := regexp_match(sisa, '^(.*?)\(([^()]*)\)(.*)$');
    hasil := hasil || m[1] || '(' || public.rhj_nama_segmen(m[2]) || ')';
    sisa := m[3];
  end loop;
  s := public.rhj_nama_huruf(hasil || sisa, campur);
  s := btrim(regexp_replace(s, '\s+', ' ', 'g'), ' ,;.-');
  return coalesce(nullif(s, ''), p);
end $$;

-- 4) sidik huruf ─────────────────────────────────────────────────────────────
create or replace function public.rhj_nama_sidik(p text)
returns text language sql immutable set search_path = public as $$
  select coalesce(string_agg(c, '' order by c), '')
    from regexp_split_to_table(lower(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g')), '') c
$$;

-- 5) normalisasi otomatis saat simpan + cadangan nama_lama dikunci ───────────
create or replace function public.customers_rapi_nama()
returns trigger language plpgsql set search_path = public as $$
declare v_mentah text; v_rapi text;
begin
  -- jalur admin (terapkan/pulihkan/migrasi) mengatur nama & nama_lama sendiri
  if coalesce(current_setting('rhj.lewati_rapi_nama', true), 'off') = 'on' then return new; end if;
  if tg_op = 'UPDATE' then
    new.nama_lama := old.nama_lama;              -- cadangan tak bisa diubah/dihapus lewat REST
    if new.nama is not distinct from old.nama then return new; end if;  -- nama sama → biarkan
  else
    new.nama_lama := null;                       -- INSERT: abaikan kiriman klien
  end if;
  v_mentah := new.nama;
  v_rapi := public.rhj_nama_rapi(v_mentah);
  if v_rapi is distinct from v_mentah then
    new.nama := v_rapi;
    if new.nama_lama is null then new.nama_lama := v_mentah; end if;   -- cadangan sekali saja
  end if;
  return new;
end $$;
drop trigger if exists customers_rapi_nama on public.customers;
create trigger customers_rapi_nama before insert or update of nama, nama_lama on public.customers
  for each row execute function public.customers_rapi_nama();

-- 6) RPC terapkan / pulihkan (tanda tangan & tipe kembali tetap) ─────────────
create or replace function public.terapkan_rapi_nama(p_ids bigint[] default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh merapikan nama pelanggan.' using errcode='42501';
  end if;
  perform set_config('rhj.lewati_rapi_nama', 'on', true);
  with upd as (
    update public.customers c
       set nama_lama = coalesce(c.nama_lama, c.nama), nama = public.rhj_nama_rapi(c.nama)
     where public.rhj_nama_rapi(c.nama) is distinct from c.nama
       and (p_ids is null or c.id = any(p_ids))
    returning 1)
  select count(*) into v_n from upd;
  perform set_config('rhj.lewati_rapi_nama', 'off', true);
  return v_n;
end $$;

create or replace function public.pulihkan_nama_pelanggan(p_ids bigint[] default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh memulihkan nama pelanggan.' using errcode='42501';
  end if;
  perform set_config('rhj.lewati_rapi_nama', 'on', true);
  with upd as (
    update public.customers c set nama = c.nama_lama, nama_lama = null
     where c.nama_lama is not null
       and public.rhj_nama_sidik(c.nama) = public.rhj_nama_sidik(c.nama_lama)  -- jangan timpa ganti-nama manual
       and (p_ids is null or c.id = any(p_ids))
    returning 1)
  select count(*) into v_n from upd;
  perform set_config('rhj.lewati_rapi_nama', 'off', true);
  return v_n;
end $$;

-- 7) kolom urut A→Z tanpa awalan badan usaha (aditif) ─────────────────────────
alter table public.customers add column if not exists nama_urut text
  generated always as (regexp_replace(lower(coalesce(nama, '')), '^(pt|cv|ud|pd|tb|fa|toko|rs)\s+', '')) stored;
create index if not exists customers_nama_urut_idx on public.customers (nama_urut, id);

-- 8) hak akses ───────────────────────────────────────────────────────────────
revoke execute on function public.rhj_nama_rapi(text), public.rhj_nama_segmen(text),
  public.rhj_nama_huruf(text, boolean), public.rhj_nama_sidik(text) from public, anon;
grant execute on function public.rhj_nama_rapi(text), public.rhj_nama_segmen(text),
  public.rhj_nama_huruf(text, boolean), public.rhj_nama_sidik(text) to authenticated, service_role;
revoke execute on function public.customers_rapi_nama() from public, anon;
revoke execute on function public.pratinjau_nama_pelanggan(), public.terapkan_rapi_nama(bigint[]),
  public.pulihkan_nama_pelanggan(bigint[]) from public, anon;
grant execute on function public.pratinjau_nama_pelanggan(), public.terapkan_rapi_nama(bigint[]),
  public.pulihkan_nama_pelanggan(bigint[]) to authenticated, service_role;

-- 9) DATA DEV: cadangan lengkap + terapkan dalam satu DO ──────────────────────
create table if not exists public.customers_nama_sebelum_100 (
  id bigint primary key, nama text not null, nama_lama text,
  diubah_oleh uuid, diubah_pada timestamptz, dicatat_pada timestamptz not null default now());
alter table public.customers_nama_sebelum_100 enable row level security;
revoke all on public.customers_nama_sebelum_100 from anon, authenticated;
do $$
begin
  insert into public.customers_nama_sebelum_100 (id, nama, nama_lama, diubah_oleh, diubah_pada)
  select id, nama, nama_lama, diubah_oleh, diubah_pada from public.customers
   where public.rhj_nama_rapi(nama) is distinct from nama
  on conflict (id) do nothing;
  perform set_config('rhj.lewati_rapi_nama', 'on', true);
  update public.customers c set nama_lama = coalesce(c.nama_lama, c.nama), nama = public.rhj_nama_rapi(c.nama)
   where public.rhj_nama_rapi(c.nama) is distinct from c.nama;
  perform set_config('rhj.lewati_rapi_nama', 'off', true);
end $$;
