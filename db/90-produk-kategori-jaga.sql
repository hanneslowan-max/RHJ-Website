-- Berkas 90 (#26): kategori produk tidak boleh hilang lagi — dimuat, dijaga trigger & CHECK.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026. Belum ke produksi.
--
-- Akar masalah (diperiksa di DEV & index.html sebelum berkas ini):
--   (a) muatSemua() memuat produk dengan daftar kolom eksplisit
--       ("/products?select=id,id_lama,kode,brand,…,usulan,usulan_teks") TANPA kategori dan TANPA
--       catatan. formProduk() lalu selalu kosong untuk keduanya, dan simpanProduk() mengirim
--       kategori:null + catatan:null → setiap simpan dari form MENIMPA kategori & catatan jadi NULL.
--       (Header berkas 63 keliru saat menyebut "Produk dimuat via select=*".) FE diperbaiki di
--       commit yang sama; trigger di bawah menjaga index.html lama yang masih mengirim null.
--   (b) Produk baru tidak pernah diberi kategori: usulkan_produk() (sales/Vonny dari PO) INSERT
--       tanpa kategori, dan sahkan_produk_usulan() tidak menyentuhnya. Produk 810/811 (usulan) dan
--       812 (usulan yang sudah disahkan owner, kelompok "Osaka Series") dibuat 18 Sep — sesudah
--       backfill berkas 63 (15 Sep) — sehingga NULL. audit_log #4595 (sahkan 812) tidak mengubah
--       kategori; NULL-nya dari (b), bukan tertimpa form.
--
-- Isi berkas:
--   (1) kolom kategori (idempoten; sudah ada sejak berkas 63) — membuat berkas ini mandiri utk PROD.
--   (2) kategori_dari_kelompok(kelompok): logika backfill berkas 63, persis sama, jadi satu fungsi.
--   (3) pulihkan HANYA baris kategori NULL memakai (2). DEV: 810, 811, 812 → 'Roda'.
--       Trigger jejak (products_jejak) dimatikan sebentar supaya diubah_oleh/diubah_pada ketiga
--       baris itu tidak tertimpa migrasi. Trigger audit (products_audit) TETAP hidup: nilai lama
--       (NULL) & baru tercatat di audit_log.
--   (4) CHECK products_kategori_sah = daftar pilihan di form. Data DEV sebelum berkas ini: Roda 770,
--       Hand Pallet 11, Hospital 11, Pallet Mesh 8, Lainnya 5, NULL 3 → semua masuk daftar, tidak
--       perlu kategori tambahan.
--   (5) trigger products_kategori (BEFORE INSERT/UPDATE):
--       • kosong/spasi → dianggap tidak diisi; ejaan huruf besar-kecil dirapikan ke daftar resmi
--       • UPDATE dengan kategori null (index.html lama selalu mengirim null) → nilai lama dipertahankan
--       • usulan disahkan (usulan true→false) dan kategorinya masih hasil otomatis dari kelompok
--         lama → diturunkan ulang dari kelompok barunya (kategori yang pernah dipilih tangan tetap)
--       • masih kosong (INSERT tanpa kategori, termasuk usulkan_produk) → diturunkan dari kelompok
--   (6) NOT NULL. Konsekuensinya kategori tidak bisa dikosongkan dengan sengaja — memang itu tujuannya.
--       CATATAN: NOT NULL ini BERGANTUNG pada trigger products_kategori. Kalau trigger dimatikan
--       atau dijatuhkan, INSERT tanpa kategori (usulkan_produk, FE lama) akan GAGAL.
--
-- Dampak: tidak ada view/fungsi lain yang membaca products.kategori (dicek via pg_depend & prosrc).
-- Urutan trigger BEFORE (alfabetis): products_jaga_kolom (berkas 92), products_jejak, products_kategori.
--
-- Membalik (bila perlu): alter table public.products alter column kategori drop not null;
--   drop trigger products_kategori on public.products; alter table public.products drop constraint
--   products_kategori_sah; lalu kembalikan nilai lama dari audit_log (DEV: update public.products
--   set kategori = null where id in (810, 811, 812)).
-- Bergantung pada: berkas 63 (kolom & logika backfill). Urutan di PROD: 63 lalu 90.

-- (1)
alter table public.products add column if not exists kategori text;

-- (2)
create or replace function public.kategori_dari_kelompok(p_kelompok text)
returns text
language sql
immutable
set search_path = public
as $$
  -- Logika = persis backfill berkas 63. Roda jadi bawaan.
  select case
    when p_kelompok ilike '%pallet mesh%' then 'Pallet Mesh'
    when p_kelompok ilike '%hand pallet%' then 'Hand Pallet'
    when p_kelompok ilike '%hospital bed%' or p_kelompok ilike '%bed equipment%' then 'Hospital'
    when p_kelompok ilike '%actuator%' then 'Lainnya'
    else 'Roda'
  end
$$;
revoke execute on function public.kategori_dari_kelompok(text) from public, anon;
grant  execute on function public.kategori_dari_kelompok(text) to authenticated, service_role;

-- (3) hanya baris NULL; kolom jejak tidak ikut berubah, audit tetap mencatat
alter table public.products disable trigger products_jejak;
update public.products
   set kategori = public.kategori_dari_kelompok(kelompok)
 where kategori is null;
alter table public.products enable trigger products_jejak;

-- (4)
alter table public.products drop constraint if exists products_kategori_sah;
alter table public.products add constraint products_kategori_sah
  check (kategori = any (array['Roda','Pallet Mesh','Hospital','Filing Cabinet','Trolley','Hand Pallet','Lainnya']));

-- (5)
create or replace function public.isi_kategori_produk()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_resmi text;
begin
  new.kategori := nullif(btrim(coalesce(new.kategori, '')), '');
  -- ejaan dirapikan ke daftar resmi ("roda" → "Roda"); yang tidak dikenal dibiarkan → ditolak CHECK
  if new.kategori is not null then
    select k into v_resmi
      from unnest(array['Roda','Pallet Mesh','Hospital','Filing Cabinet','Trolley','Hand Pallet','Lainnya']) k
     where lower(k) = lower(new.kategori)
     limit 1;
    if v_resmi is not null then new.kategori := v_resmi; end if;
  end if;

  if tg_op = 'UPDATE' then
    -- index.html lama tidak memuat kategori lalu mengirim kategori:null setiap simpan
    if new.kategori is null then
      new.kategori := old.kategori;
    end if;
    -- usulan disahkan: kategori otomatis ikut kelompok barunya, kecuali pernah dipilih tangan
    if old.usulan and not new.usulan
       and new.kategori is not distinct from old.kategori
       and old.kategori is not distinct from public.kategori_dari_kelompok(old.kelompok) then
      new.kategori := public.kategori_dari_kelompok(new.kelompok);
    end if;
  end if;

  if new.kategori is null then
    new.kategori := public.kategori_dari_kelompok(new.kelompok);
  end if;
  return new;
end $$;
revoke execute on function public.isi_kategori_produk() from public, anon;

drop trigger if exists products_kategori on public.products;
create trigger products_kategori
  before insert or update on public.products
  for each row execute function public.isi_kategori_produk();

-- (6) — gagal di sini kalau masih ada NULL (seharusnya 0 sesudah langkah 3)
alter table public.products alter column kategori set not null;

comment on column public.products.kategori is
  '#26: kategori produk untuk laporan (Roda, Pallet Mesh, Hospital, Filing Cabinet, Trolley, Hand Pallet, Lainnya). NOT NULL dijaga trigger products_kategori: kosong = diturunkan dari kelompok (kategori_dari_kelompok), UPDATE null = nilai lama.';
