-- ═══════════════════════════════════════════════════════════════════════
-- 141 · EHC tahap 3 (1/3) — STRUKTUR: periode 19–18, pemeriksaan GM per
--       klaim, daftar bayar finance tgl 20
--
-- Jalankan 141 → 142 → 143 berturut-turut (boleh satu transaksi). Bila 142
-- atau 143 gagal, perbaiki lalu jalankan ulang berkas itu. Sesudah 141 saja
-- sistem tetap aman (gagal-tertutup): jalur EHC lama tertutup —
-- ajukan_transfer('ehc') ditolak 0A000 (bagian 0b), setujui EHC cepat versi
-- lama ditolak mesin status/CHECK (bagian 5 & 6a), rekap_transfer('ehc') dan
-- rekap_ehc_cepat lama ditolak mesin status — tidak ada klaim yang tertahan.
--
-- Isi berkas ini (urutan penting; 142 = fungsi/RPC, 143 = view):
--   0. pra-cek gagal-tertutup (pengajuan transfer EHC lama harus tuntas;
--      transfer_pengajuan dikunci sampai transaksi selesai)
--   0b. ajukan_transfer: blok 'ehc' diganti penolakan 0A000 (dibangun dari
--      definisi DEV hidup; cabang komisi tidak disentuh) — satu transaksi
--      dengan pra-cek, jadi tidak ada pengajuan EHC baru sesudah 141
--   1. periode_bayar_ehc(date): tgl ≥ 20 → bulan itu, selain itu bulan lalu
--   2. kolom putusan GM di ehc_klaim (gm_oleh/gm_pada/gm_catatan/gm_jalur,
--      ditransfer_pada) + transfer_batch.periode_bayar
--   3. tabel baru ehc_klaim_tujuan (rekening yang DIKUNCI saat GM setuju)
--      dan ehc_klaim_putusan (jejak putusan append-only)
--   4. konversi data lama: klaim ber-batch → 'disetujui' (konversi);
--      cepat disetujui belum ber-batch → 'disetujui' (jalur cepat)
--   5. CHECK & indeks baru (dipasang SESUDAH konversi), termasuk
--      ehck_cepat_ok_diputus: EHC cepat yang disetujui tidak pernah
--      tertinggal berstatus 'diajukan'
--   6. penjaga: mesin status ehc_klaim, anak klaim (alokasi/berkas) beku
--      sesudah diputus, riwayat tetap, tandai ditransfer saat referensi
--      bank diisi, jaga_batch dikeraskan, jaga_nilai_terkunci (cabang EHC,
--      dibangun dari definisi DEV hidup), periksa_saldo_ehc_sp
--   7. hak baca (keputusan P4) + salinan rekening dibuang dari ehc_klaim_log
--      (hak baca kolom rekening di kepala ehc_klaim dicabut di AKHIR 143)
--
-- Keputusan Hannes 9 Okt 2026 (RANCANGAN-EHC-TAHAP3.md):
--   P1 GM/owner BOLEH memutus klaim yang ia buat/ubah/minta cepat — cukup
--      tercatat siapa yang memutus (gm_oleh + ehc_klaim_putusan). Tidak ada
--      fungsi "pemutus terlibat". Persetujuan massal tetap melewati lintas.
--   P2 Tolak EHC cepat = hanya pencairan cepatnya ditolak; klaim tetap
--      'diajukan' dan ikut pemeriksaan GM sesudah tgl 18.
--   P3 Klaim ditolak sesudah komisi SP diklaim → saldo yang kembali masuk
--      kas sales (tidak ada perubahan hitungan: ehc_saldo_sp/kas_sales).
--   P4 Vonny, Lie Sian, Ichi TIDAK melihat klaim EHC: hak baca ehc_klaim &
--      ehc_cepat_log dipersempit ke boleh_lihat_nilai_klaim() (owner, GM,
--      staff, finance, Lenni) atau sales pemilik klaim. Akibatnya hitungan
--      klaim_ehc di view sales_beban menjadi 0 untuk ketiga peran itu.
--
-- Status klaim tetap 4 nilai: diajukan (≤ cutoff bisa diubah sales; sesudah
-- cutoff menunggu GM) · disetujui (diputus GM: periksa / cepat / konversi) ·
-- ditolak (final, saldo kembali) · batal. transfer_batch_id = masuk daftar
-- bayar; ditransfer_pada = referensi bank terisi = uang keluar.
--
-- Batas alat: berkas ini tanpa kata hapus berbahasa Inggris maupun DDL
-- pembuang; FK baru tanpa klausa hapus; trigger audit tabel baru hanya
-- insert/update (tabel append-only, tanpa hak hapus untuk siapa pun).
-- Data lama tidak dihapus. Di DEV konversi (bagian 4) menyentuh 0 baris.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 0. pra-cek gagal-tertutup ───────────────────────────────────────────
-- transfer_pengajuan dikunci (share row exclusive, sampai transaksi selesai)
-- supaya tidak ada pengajuan EHC yang lahir di antara pra-cek dan bagian 0b.
do $$
declare v_n integer;
begin
  lock table public.transfer_pengajuan in share row exclusive mode;
  if to_regclass('public.ehc_klaim_alokasi') is null then
    raise exception 'Berkas 141 butuh berkas 140 (ehc_klaim_alokasi belum ada).';
  end if;
  if exists (select 1 from pg_constraint where conname = 'ehck_cara_bayar_sah'
                and conrelid = 'public.ehc_klaim'::regclass) then
    raise exception 'Berkas 141 butuh 140b (CHECK cara bayar lama ehck_cara_bayar_sah masih ada).';
  end if;
  select count(*) into v_n from public.transfer_pengajuan
   where jenis = 'ehc' and status in ('menunggu','disetujui');
  if v_n > 0 then
    raise exception 'Berkas 141 berhenti: masih ada % pengajuan transfer EHC yang menunggu/disetujui. '
                    'Tuntaskan dulu lewat alur lama (putuskan_transfer lalu rekap_transfer, atau '
                    'tarik_pengajuan_transfer), lalu jalankan ulang.', v_n;
  end if;
  select count(*) into v_n from public.ehc_klaim
   where transfer_batch_id is not null and status not in ('diajukan','disetujui');
  if v_n > 0 then
    raise exception 'Berkas 141 berhenti: % klaim EHC ber-batch berstatus batal/ditolak — periksa manual.', v_n;
  end if;
  select count(*) into v_n from public.sales_orders
   where ehc_dini_minta and not coalesce(ehc_dini_ok, false) and not batal;
  raise notice '141: % SP masih meminta EHC dini (cabang antrean ehc_dini dibuang di 143; jalurnya kini EHC cepat).', v_n;
end $$;

-- ── 0b. ajukan_transfer: hanya blok 'ehc' yang diganti ───────────────────
-- Dibangun dari definisi DEV hidup (dipakai bersama alur komisi tgl 25):
-- blok "if p_jenis = 'ehc' and … cutoff … end if;" diganti penolakan 0A000;
-- seluruh teks lain (cabang komisi) tetap byte-identik. Pola harus cocok
-- tepat satu kali. Ada di 141 (bukan 142) supaya pintu pengajuan EHC lama
-- tertutup dalam transaksi yang sama dengan pra-cek bagian 0. Penanda
-- idempoten: "(berkas 141)", juga menerima "(berkas 142)" dari draf lama.
do $$
declare
  v_def  text;
  v_pola text := $p$if p_jenis = 'ehc' and public.hari_ini_wib() <= public.cutoff_ehc(p_bulan) then$p$;
  v_baru text := $b$if p_jenis = 'ehc' then
    raise exception 'Pembayaran EHC tidak lagi lewat pengajuan transfer (berkas 141): GM memeriksa per klaim sesudah tgl 18, finance mengunci daftar bayar mulai tgl 20 (rekap_ehc_bulanan).'
      using errcode = '0A000';
  end if;$b$;
  v_a integer; v_e integer; v_n integer;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ajukan_transfer' and p.prokind = 'f';
  if v_def is null then raise exception '141: ajukan_transfer tidak ada di DB.'; end if;
  if strpos(v_def, '(berkas 141)') > 0 or strpos(v_def, '(berkas 142)') > 0 then
    raise notice '141: ajukan_transfer sudah menolak EHC.';
    return;
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_pola, ''))) / length(v_pola);
  if v_n <> 1 then
    raise exception '141: blok EHC ajukan_transfer ditemukan % kali (harus 1) — definisi DEV berubah, periksa manual.', v_n;
  end if;
  v_a := strpos(v_def, v_pola);
  v_e := strpos(substr(v_def, v_a), 'end if;');
  if v_e = 0 then raise exception '141: akhir blok EHC ajukan_transfer tidak ditemukan.'; end if;
  execute left(v_def, v_a - 1) || v_baru || substr(v_def, v_a + v_e - 1 + length('end if;'));
end $$;
revoke all on function public.ajukan_transfer(text, text, text) from public, anon;
grant execute on function public.ajukan_transfer(text, text, text) to authenticated;

-- ── 1. periode bayar ─────────────────────────────────────────────────────
-- Finance mengunci daftar bayar periode X mulai tgl 20 (WIB) bulan X.
-- 9 Okt → 2026-09; 20 Okt → 2026-10.
create or replace function public.periode_bayar_ehc(p_tgl date)
returns text language sql immutable set search_path = public as $$
  select to_char(case when extract(day from p_tgl) >= 20 then p_tgl
                      else (date_trunc('month', p_tgl) - interval '1 month')::date end, 'YYYY-MM')
$$;
revoke all on function public.periode_bayar_ehc(date) from public, anon;
grant execute on function public.periode_bayar_ehc(date) to authenticated;

-- ── 2. kolom baru ────────────────────────────────────────────────────────
alter table public.ehc_klaim
  add column if not exists gm_oleh         uuid references auth.users(id),
  add column if not exists gm_pada         timestamptz,
  add column if not exists gm_catatan      text,
  add column if not exists gm_jalur        text,
  add column if not exists ditransfer_pada timestamptz;
comment on column public.ehc_klaim.gm_jalur is
  'Jalur putusan GM (berkas 141): periksa (sesudah cutoff, per klaim) / cepat (EHC cepat) / konversi (data lama).';
comment on column public.ehc_klaim.ditransfer_pada is
  'Diisi otomatis saat referensi bank batch diisi = uang keluar (berkas 141). Batch tanpa referensi belum dianggap dibayar.';

alter table public.transfer_batch add column if not exists periode_bayar text;
comment on column public.transfer_batch.periode_bayar is
  'Periode EHC yang dibayar batch bulanan (berkas 141). Null untuk batch komisi, batch EHC cepat, dan batch lama.';

-- ── 3. tabel baru ────────────────────────────────────────────────────────
-- Rekening tujuan yang dikunci saat GM setuju: koreksi rekening sesudahnya
-- tidak ikut, finance tidak bisa mengalihkan tujuan. Baca setara srr_baca.
create table if not exists public.ehc_klaim_tujuan (
  klaim_id     bigint primary key references public.ehc_klaim(id),
  sumber       text not null,
  pic_id       bigint references public.customer_pics(id),
  bank         text,
  no_rekening  text,
  atas_nama    text,
  dikunci_oleh uuid references auth.users(id),
  dikunci_pada timestamptz not null default now(),
  constraint ekt_sumber_sah check (sumber in ('pic','sales','tunai')),
  constraint ekt_pic_sah check (sumber <> 'pic' or pic_id is not null),
  constraint ekt_rekening_sah check (case when sumber = 'tunai'
      then coalesce(btrim(bank), '') = '' and coalesce(btrim(no_rekening), '') = ''
      else coalesce(btrim(bank), '') <> '' and coalesce(btrim(no_rekening), '') <> '' end)
);
comment on table public.ehc_klaim_tujuan is
  'Rekening tujuan klaim EHC yang dikunci saat GM menyetujui (berkas 141): pic = PIC customer, sales = rekening sales (reimburse), tunai.';

create table if not exists public.ehc_klaim_putusan (
  id       bigserial primary key,
  klaim_id bigint not null references public.ehc_klaim(id),
  jalur    text not null,
  aksi     text not null,
  catatan  text,
  snapshot jsonb not null default '{}'::jsonb,
  oleh     uuid references auth.users(id),
  pada     timestamptz not null default now(),
  constraint ekp_jalur_sah check (jalur in ('periksa','cepat','konversi','bayar')),
  constraint ekp_aksi_sah  check (aksi in ('setuju','tolak','keluar_batch')),
  constraint ekp_jalur_aksi check ((jalur = 'bayar') = (aksi = 'keluar_batch')),
  constraint ekp_beralasan check (aksi = 'setuju' or coalesce(btrim(catatan), '') <> '')
);
comment on table public.ehc_klaim_putusan is
  'Jejak putusan klaim EHC (berkas 141), append-only: setuju/tolak GM (periksa/cepat/konversi) dan keluar dari batch (bayar).';
create unique index if not exists ekp_setuju_uniq on public.ehc_klaim_putusan (klaim_id) where aksi = 'setuju';
create index if not exists ekp_klaim_idx on public.ehc_klaim_putusan (klaim_id, id desc);

alter table public.ehc_klaim_tujuan  enable row level security;
alter table public.ehc_klaim_putusan enable row level security;
revoke all on public.ehc_klaim_tujuan  from public, anon, authenticated;
revoke all on public.ehc_klaim_putusan from public, anon, authenticated;
revoke all on sequence public.ehc_klaim_putusan_id_seq from public, anon, authenticated;
grant select on public.ehc_klaim_tujuan  to authenticated;
grant select on public.ehc_klaim_putusan to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'ehc_klaim_tujuan' and policyname = 'ekt_baca') then
    create policy ekt_baca on public.ehc_klaim_tujuan for select to authenticated
      using (public.peran_saya() in ('owner','gm','finance') or public.klaim_ehc_saya(klaim_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'ehc_klaim_putusan' and policyname = 'ekp_baca') then
    create policy ekp_baca on public.ehc_klaim_putusan for select to authenticated
      using (public.boleh_lihat_nilai_klaim() or public.klaim_ehc_saya(klaim_id));
  end if;
end $$;

-- ── 4. konversi data lama (sebelum CHECK & trigger) ──────────────────────
do $$
declare v_a integer; v_c integer; v_x integer; v_t integer; v_p integer; v_lewat integer;
begin
  -- (a)+(b) klaim ber-batch (alur lama) → disetujui, konversi
  update public.ehc_klaim k
     set status = 'disetujui', gm_jalur = 'konversi',
         gm_pada = coalesce(b.dibuat_pada, k.dibuat_pada),
         gm_catatan = 'Konversi 141: dibayar lewat alur lama (batch #' || b.id || ')',
         ditransfer_pada = coalesce(b.ref_pada, b.dibuat_pada)
    from public.transfer_batch b
   where b.id = k.transfer_batch_id and k.gm_jalur is null and k.status in ('diajukan','disetujui');
  get diagnostics v_a = row_count;
  -- (c) EHC cepat disetujui GM, belum ber-batch → disetujui jalur cepat
  update public.ehc_klaim k
     set status = 'disetujui', gm_jalur = 'cepat', gm_oleh = k.cepat_diputus_oleh,
         gm_pada = coalesce(k.cepat_diputus_pada, k.cepat_diminta_pada, k.dibuat_pada),
         gm_catatan = k.cepat_catatan
   where k.status in ('diajukan','disetujui') and k.transfer_batch_id is null and k.gm_jalur is null
     and k.cepat_minta and coalesce(k.cepat_ok, false);
  get diagnostics v_c = row_count;
  -- sisa disetujui/ditolak tanpa jejak putusan (tidak terduga) → konversi
  update public.ehc_klaim k
     set gm_jalur = 'konversi', gm_pada = coalesce(k.diubah_pada, k.dibuat_pada),
         gm_catatan = coalesce(nullif(btrim(k.gm_catatan), ''), 'Konversi 141: berstatus ' || k.status || ' sebelum 141')
   where k.status in ('disetujui','ditolak') and k.gm_jalur is null;
  get diagnostics v_x = row_count;
  -- tujuan dari kepala klaim (reimburse kosong → rekening sales saat ini)
  insert into public.ehc_klaim_tujuan (klaim_id, sumber, pic_id, bank, no_rekening, atas_nama, dikunci_oleh, dikunci_pada)
  select k.id, x.sumber, case when x.sumber = 'pic' then k.pic_id end,
         case when x.sumber <> 'tunai' then x.bank end, case when x.sumber <> 'tunai' then x.norek end,
         case when x.sumber <> 'tunai' then x.an end, k.gm_oleh, coalesce(k.gm_pada, now())
    from public.ehc_klaim k
    left join public.sales_rep_rekening r on r.sales_rep_id = k.sales_rep_id
   cross join lateral (
     select case k.cara_bayar when 'transfer' then 'pic' when 'reimburse' then 'sales' when 'tunai' then 'tunai' end as sumber,
            case when k.cara_bayar = 'reimburse' and coalesce(btrim(k.no_rekening), '') = '' then r.bank else k.bank end as bank,
            case when k.cara_bayar = 'reimburse' and coalesce(btrim(k.no_rekening), '') = '' then r.no_rekening else k.no_rekening end as norek,
            case when k.cara_bayar = 'reimburse' and coalesce(btrim(k.no_rekening), '') = '' then r.atas_nama else k.atas_nama end as an) x
   where k.status = 'disetujui' and k.gm_jalur in ('konversi','cepat')
     and not exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id)
     and x.sumber is not null
     and (x.sumber <> 'pic' or k.pic_id is not null)
     and (x.sumber = 'tunai' or (coalesce(btrim(x.bank), '') <> '' and coalesce(btrim(x.norek), '') <> ''));
  get diagnostics v_t = row_count;
  select count(*) into v_lewat from public.ehc_klaim k
   where k.status = 'disetujui' and k.transfer_batch_id is null
     and not exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id);
  insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh, pada)
  select k.id, 'konversi', 'setuju', k.gm_catatan,
         jsonb_build_object('konversi', '141', 'gm_jalur', k.gm_jalur, 'batch', k.transfer_batch_id,
                            'nominal', n.nominal, 'cepat_alasan', k.cepat_alasan),
         k.gm_oleh, coalesce(k.gm_pada, now())
    from public.ehc_klaim k left join public.ehc_klaim_nilai n on n.klaim_id = k.id
   where k.status = 'disetujui' and k.gm_jalur in ('konversi','cepat')
     and not exists (select 1 from public.ehc_klaim_putusan p where p.klaim_id = k.id and p.aksi = 'setuju');
  get diagnostics v_p = row_count;
  raise notice '141 konversi: ber-batch %, cepat %, lain %, tujuan %, putusan %; disetujui belum ber-batch tanpa tujuan: %',
               v_a, v_c, v_x, v_t, v_p, v_lewat;
end $$;

-- ── 5. CHECK & indeks ────────────────────────────────────────────────────
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ehck_gm_jalur_sah') then
    alter table public.ehc_klaim add constraint ehck_gm_jalur_sah
      check (gm_jalur is null or gm_jalur in ('periksa','cepat','konversi'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_putusan_lengkap') then
    alter table public.ehc_klaim add constraint ehck_putusan_lengkap
      check (status not in ('disetujui','ditolak') or (gm_pada is not null and gm_jalur is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_tolak_beralasan') then
    alter table public.ehc_klaim add constraint ehck_tolak_beralasan
      check (status <> 'ditolak' or coalesce(btrim(gm_catatan), '') <> '');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_bayar_disetujui') then
    alter table public.ehc_klaim add constraint ehck_bayar_disetujui
      check (transfer_batch_id is null or status = 'disetujui');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_ditransfer_berbatch') then
    alter table public.ehc_klaim add constraint ehck_ditransfer_berbatch
      check (ditransfer_pada is null or transfer_batch_id is not null);
  end if;
  -- EHC cepat yang disetujui = klaimnya diputus sekaligus (status
  -- 'disetujui', jalur cepat). Kebalikan persis konversi (c) di bagian 4,
  -- jadi tidak ada baris lama yang melanggar. Menutup putuskan_klaim_cepat
  -- versi lama di jeda 141→142 (setujui gagal 23514 tanpa mengubah apa pun;
  -- tolak cepat P2 tetap boleh) dan berlaku permanen sesudahnya.
  if not exists (select 1 from pg_constraint where conname = 'ehck_cepat_ok_diputus') then
    alter table public.ehc_klaim add constraint ehck_cepat_ok_diputus
      check (status <> 'diajukan' or not (coalesce(cepat_minta, false) and coalesce(cepat_ok, false)));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tb_periode_bayar_sah') then
    alter table public.transfer_batch add constraint tb_periode_bayar_sah
      check (periode_bayar is null or periode_bayar ~ '^\d{4}-\d{2}$');
  end if;
end $$;
create index if not exists ehck_periksa_idx on public.ehc_klaim (periode)
  where status = 'diajukan' and transfer_batch_id is null;
-- Satu daftar bayar bulanan berisi per periode. Batch yang seluruh isinya
-- dikeluarkan (jumlah 0) tidak menahan kunci ulang; batch lama (null) bebas.
create unique index if not exists tb_ehc_periode_uniq on public.transfer_batch (jenis, periode_bayar)
  where periode_bayar is not null and not cepat and jumlah_klaim > 0;

-- ── 6. penjaga ───────────────────────────────────────────────────────────
-- 6a. Mesin status ehc_klaim. Perpindahan sah: diajukan → disetujui |
-- ditolak | batal; disetujui → batal hanya bila belum ber-batch; ditolak &
-- batal final. Setujui EHC cepat (cepat_ok jadi true) hanya bersama status
-- 'disetujui' (pesan jelas untuk layar lama; invarian: ehck_cepat_ok_diputus).
-- Putusan GM (gm_*) hanya berubah bersama perpindahan dari
-- diajukan. Batch & ditransfer_pada hanya lewat rhj.batch='on'. Sesudah
-- keluar dari 'diajukan' semua kolom beku kecuali sales_rep_id
-- (gabungkan_sales / batalkan_ubah_sales) dan kolom jalur bayar/batal.
create or replace function public.jaga_status_klaim_ehc()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_batch boolean := coalesce(current_setting('rhj.batch', true), '') = 'on';
  v_bebas text[] := array['sales_rep_id','status','batal_alasan','batal_oleh','batal_pada',
                          'transfer_batch_id','ditransfer_pada'];
begin
  if tg_op = 'INSERT' then
    if new.status <> 'diajukan' or new.transfer_batch_id is not null or new.ditransfer_pada is not null
       or new.gm_oleh is not null or new.gm_pada is not null or new.gm_catatan is not null or new.gm_jalur is not null then
      raise exception 'Klaim EHC baru selalu berstatus diajukan, tanpa putusan GM dan tanpa batch.' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.status is distinct from old.status
     and not ((old.status = 'diajukan' and new.status in ('disetujui','ditolak','batal'))
              or (old.status = 'disetujui' and new.status = 'batal' and old.transfer_batch_id is null)) then
    raise exception 'Status klaim EHC #% tidak bisa berpindah dari % ke %.', old.id, old.status, new.status
      using errcode = '42501';
  end if;
  if new.cepat_ok is true and old.cepat_ok is distinct from true and new.status = 'diajukan' then
    raise exception 'Persetujuan EHC cepat klaim #% harus sekaligus memutus klaimnya (putuskan_klaim_cepat_v, berkas 142) — muat ulang halaman.', old.id
      using errcode = '42501';
  end if;
  if (new.gm_oleh, new.gm_pada, new.gm_catatan, new.gm_jalur)
       is distinct from (old.gm_oleh, old.gm_pada, old.gm_catatan, old.gm_jalur)
     and not (old.status = 'diajukan' and new.status in ('disetujui','ditolak')) then
    raise exception 'Putusan GM klaim EHC #% tidak bisa diubah — putusan hanya lewat putuskan_klaim_ehc / putuskan_klaim_cepat.', old.id
      using errcode = '42501';
  end if;
  if (new.batal_alasan, new.batal_oleh, new.batal_pada) is distinct from (old.batal_alasan, old.batal_oleh, old.batal_pada)
     and not (new.status = 'batal' and old.status <> 'batal') then
    raise exception 'Data pembatalan klaim EHC #% hanya diisi saat klaim dibatalkan.', old.id using errcode = '42501';
  end if;
  if new.transfer_batch_id is distinct from old.transfer_batch_id then
    if old.transfer_batch_id is null then
      if not (v_batch and new.status = 'disetujui') then
        raise exception 'Klaim EHC #% hanya masuk batch bila sudah disetujui GM, lewat rekap finance.', old.id
          using errcode = '42501';
      end if;
    elsif new.transfer_batch_id is null then
      if not (v_batch and old.ditransfer_pada is null and new.ditransfer_pada is null) then
        raise exception 'Klaim EHC #% hanya keluar dari batch lewat keluarkan_klaim_ehc_batch, sebelum referensi bank diisi.', old.id
          using errcode = '42501';
      end if;
    else
      raise exception 'Klaim EHC #% tidak bisa dipindah ke batch lain.', old.id using errcode = '42501';
    end if;
  end if;
  if new.ditransfer_pada is distinct from old.ditransfer_pada
     and not (old.ditransfer_pada is null and new.transfer_batch_id is not null and v_batch) then
    raise exception 'Tanda ditransfer klaim EHC #% hanya diisi otomatis saat referensi bank batch diisi.', old.id
      using errcode = '42501';
  end if;
  if old.status <> 'diajukan' and (to_jsonb(new) - v_bebas) is distinct from (to_jsonb(old) - v_bebas) then
    raise exception 'Klaim EHC #% sudah berstatus % — isinya tidak bisa diubah lagi.', old.id, old.status
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_status_klaim_ehc() from public, anon, authenticated;
create or replace trigger ehck_jaga_status
  before insert or update on public.ehc_klaim
  for each row execute function public.jaga_status_klaim_ehc();

-- 6b. Alokasi & lampiran hanya berubah selama klaim masih diajukan dan
-- belum ber-batch (satu-satunya penulis: simpan_klaim_ehc).
create or replace function public.jaga_anak_klaim_ehc()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ids bigint[] := array[new.klaim_id];
begin
  if tg_op = 'UPDATE' then v_ids := v_ids || old.klaim_id; end if;
  if exists (select 1 from public.ehc_klaim k
              where k.id = any(v_ids) and (k.status <> 'diajukan' or k.transfer_batch_id is not null)) then
    raise exception 'Klaim EHC #% sudah diputus atau ber-batch — alokasi SP dan lampirannya beku.', new.klaim_id
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_anak_klaim_ehc() from public, anon, authenticated;
create or replace trigger ekal_jaga
  before insert or update on public.ehc_klaim_alokasi
  for each row execute function public.jaga_anak_klaim_ehc();
create or replace trigger ekb_jaga
  before insert or update on public.ehc_klaim_berkas
  for each row execute function public.jaga_anak_klaim_ehc();

-- 6c. Riwayat tetap.
create or replace function public.jaga_riwayat_tetap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Riwayat tidak bisa diubah (%).', tg_table_name using errcode = '42501';
end $$;
revoke all on function public.jaga_riwayat_tetap() from public, anon, authenticated;
create or replace trigger ekt_tetap before update on public.ehc_klaim_tujuan
  for each row execute function public.jaga_riwayat_tetap();
create or replace trigger ekp_tetap before update on public.ehc_klaim_putusan
  for each row execute function public.jaga_riwayat_tetap();
create or replace trigger zz_audit_ehc_klaim_tujuan after insert or update on public.ehc_klaim_tujuan
  for each row execute function public.catat_perubahan_kunci('klaim_id');
create or replace trigger zz_audit_ehc_klaim_putusan after insert or update on public.ehc_klaim_putusan
  for each row execute function public.catat_perubahan();

-- 6d. Referensi bank batch EHC diisi → klaim di batch itu ditransfer.
create or replace function public.tandai_ehc_ditransfer()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_lama text := current_setting('rhj.batch', true);
begin
  perform set_config('rhj.batch', 'on', true);
  update public.ehc_klaim set ditransfer_pada = now()
   where transfer_batch_id = new.id and ditransfer_pada is null;
  perform set_config('rhj.batch', coalesce(v_lama, ''), true);
  return null;
end $$;
revoke all on function public.tandai_ehc_ditransfer() from public, anon, authenticated;
create or replace trigger tb_tandai_ditransfer
  after update of no_referensi on public.transfer_batch
  for each row
  when (old.no_referensi is null and new.no_referensi is not null and new.jenis = 'ehc')
  execute function public.tandai_ehc_ditransfer();

-- 6e. jaga_batch dikeraskan (dari definisi DEV): pembuat, waktu dibuat, dan
-- periode bayar beku; referensi yang sudah terisi tidak bisa dikosongkan dan
-- isinya beku; ref_oleh/ref_pada hanya diisi sistem. Jalur rhj.batch untuk
-- rekap komisi tetap sama.
create or replace function public.jaga_batch()
returns trigger language plpgsql security definer set search_path = public as $function$
begin
  if new.dibuat_oleh is distinct from old.dibuat_oleh
  or new.dibuat_pada is distinct from old.dibuat_pada
  or new.periode_bayar is distinct from old.periode_bayar then
    raise exception 'Batch transfer #%: pembuat, waktu dibuat, dan periode bayar tidak bisa diubah.', old.id
      using errcode = '42501';
  end if;
  if new.no_referensi is distinct from old.no_referensi and btrim(new.no_referensi) = '' then
    raise exception 'Nomor referensi batch #% tidak boleh kosong.', old.id using errcode = '22023';
  end if;
  if old.no_referensi is not null then
    if new.no_referensi is null then
      raise exception 'Batch transfer #% sudah berreferensi bank — referensinya tidak bisa dikosongkan.', old.id
        using errcode = '42501';
    end if;
    if new.jumlah_klaim is distinct from old.jumlah_klaim or new.total is distinct from old.total then
      raise exception 'Batch transfer #% sudah berreferensi bank — isinya beku.', old.id using errcode = '42501';
    end if;
  end if;
  if new.no_referensi is distinct from old.no_referensi then
    new.ref_oleh := auth.uid();
    new.ref_pada := now();
  else
    new.ref_oleh := old.ref_oleh;
    new.ref_pada := old.ref_pada;
  end if;
  if coalesce(current_setting('rhj.batch', true), '') = 'on' then
    return new;
  end if;
  if new.jenis        is distinct from old.jenis
  or new.bulan        is distinct from old.bulan
  or new.tanggal      is distinct from old.tanggal
  or new.jumlah_klaim is distinct from old.jumlah_klaim
  or new.total        is distinct from old.total
  or new.cepat        is distinct from old.cepat then
    raise exception
      'Batch transfer #% tidak bisa diubah isinya. Yang masih boleh diisi cuma nomor '
      'referensi bank dan catatan. Angka dan tanggalnya adalah cap waktu — begitu bisa '
      'diedit, ia berhenti jadi bukti.', old.id;
  end if;
  return new;
end $function$;

-- 6f. jaga_nilai_terkunci — dipakai bersama komisi (kkn_kunci_batch).
-- Dibangun dari definisi DEV hidup: hanya cabang EHC yang ditambah (nominal
-- & kas beku begitu klaim keluar dari 'diajukan'); cabang komisi tidak
-- disentuh. Pola harus cocok tepat satu kali.
do $$
declare
  v_def   text;
  v_pola  text := $p$v_jenis := 'EHC'; v_kode := 'ehc';$p$;
  v_sisip text := $s$
    if (new.nominal is distinct from old.nominal or new.kas is distinct from old.kas)
       and exists (select 1 from public.ehc_klaim k where k.id = new.klaim_id and k.status <> 'diajukan') then
      raise exception 'Nominal klaim EHC ini sudah diputus GM (berkas 141) — tidak bisa diubah lagi.' using errcode = '42501';
    end if;$s$;
  v_n     integer;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'jaga_nilai_terkunci' and p.prokind = 'f';
  if v_def is null then raise exception '141: jaga_nilai_terkunci tidak ada di DB.'; end if;
  if strpos(v_def, '(berkas 141)') > 0 then
    raise notice '141: jaga_nilai_terkunci sudah memuat cabang 141.';
    return;
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_pola, ''))) / length(v_pola);
  if v_n <> 1 then
    raise exception '141: pola cabang EHC jaga_nilai_terkunci ditemukan % kali (harus 1) — definisi DEV berubah, periksa manual.', v_n;
  end if;
  execute replace(v_def, v_pola, v_pola || v_sisip);
end $$;

-- 6g. SP tidak bisa dibatalkan selama ada klaim yang uangnya belum keluar:
-- "belum keluar" kini = ditransfer_pada kosong (termasuk EHC cepat yang
-- sudah disetujui dan klaim di batch tanpa referensi). Selebihnya sama
-- dengan definisi DEV (berkas 140).
create or replace function public.periksa_saldo_ehc_sp(p_so bigint)
returns void language plpgsql security definer set search_path = public as $function$
declare v_terpakai numeric; v_belum numeric; v_total numeric; v_batal boolean; v_no text;
begin
  if p_so is null then return; end if;
  select coalesce(sum(a.nominal), 0),
         coalesce(sum(a.nominal) filter (where k.ditransfer_pada is null), 0)
    into v_terpakai, v_belum
    from public.ehc_klaim_alokasi a join public.ehc_klaim k on k.id = a.klaim_id
   where a.so_id = p_so and k.status in ('diajukan','disetujui');
  if v_terpakai = 0 then return; end if;

  select s.batal, s.no_sp into v_batal, v_no from public.sales_orders s where s.id = p_so;
  if not found then return; end if;
  if v_batal then
    if v_belum > 0 then
      raise exception 'SP % tidak bisa dibatalkan: saldo EHC-nya masih dipakai klaim EHC yang belum dibayar (%). '
                      'Batalkan klaim EHC-nya dulu — sales sebelum cutoff, owner/GM kapan saja.',
                      v_no, public.rp_teks(v_belum) using errcode = '23514';
    end if;
    return;
  end if;
  select trunc(coalesce(r.total_ehc, 0), 2) into v_total from public.so_ringkas r where r.so_id = p_so;
  if coalesce(v_total, 0) < v_terpakai then
    raise exception 'EHC SP % tinggal % sesudah perubahan ini, padahal klaim EHC aktif atas SP ini sudah %. '
                    'Ubah atau batalkan klaim EHC-nya dulu.',
                    v_no, public.rp_teks(coalesce(v_total, 0)), public.rp_teks(v_terpakai)
      using errcode = '23514';
  end if;
end $function$;
revoke all on function public.periksa_saldo_ehc_sp(bigint) from public, anon, authenticated;

-- ── 7. hak baca (P4) ─────────────────────────────────────────────────────
-- Klaim EHC & riwayat cepatnya hanya owner, GM, staff, finance, Lenni, dan
-- sales pemilik klaim. Vonny, Lie Sian, Ichi tidak lagi melihatnya.
alter policy ehck_baca on public.ehc_klaim
  using (public.boleh_lihat_nilai_klaim() or public.klaim_ehc_saya(id));
alter policy ecl_baca on public.ehc_cepat_log
  using (public.boleh_lihat_nilai_klaim() or public.klaim_ehc_saya(klaim_id));

-- Rekening tujuan hanya owner/GM/finance dan sales pemilik (setara srr_baca,
-- prinsip 139k). simpan_klaim_ehc (tidak disentuh) menyalin rekening —
-- untuk reimburse = rekening pribadi sales — ke kepala ehc_klaim dan, saat
-- 'ubah', ke ehc_klaim_log.data->'klaim' (to_jsonb), yang terbaca staff &
-- Lenni. Salinan di log dibuang di sini (nilai asli tetap di audit
-- zz_audit_ehc_klaim); hak baca kolom rekening di kepala ehc_klaim dicabut
-- di AKHIR 143 (sesudah ehc_cepat_siap membaca ehc_klaim_tujuan).
create or replace function public.ehc_log_tanpa_rekening()
returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if jsonb_typeof(new.data -> 'klaim') = 'object' then
    new.data := jsonb_set(new.data, '{klaim}', (new.data -> 'klaim') - array['bank','no_rekening','atas_nama']);
  end if;
  return new;
end $f$;
revoke all on function public.ehc_log_tanpa_rekening() from public, anon, authenticated;
create or replace trigger ekl_tanpa_rekening before insert or update on public.ehc_klaim_log
  for each row execute function public.ehc_log_tanpa_rekening();
update public.ehc_klaim_log
   set data = jsonb_set(data, '{klaim}', (data -> 'klaim') - array['bank','no_rekening','atas_nama'])
 where jsonb_typeof(data -> 'klaim') = 'object'
   and (data -> 'klaim') ?| array['bank','no_rekening','atas_nama'];
