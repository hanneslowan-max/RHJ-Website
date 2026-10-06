-- DRAF — BELUM diuji, BELUM dijalankan di DEV (sedang diuji rancangannya). Jangan dijalankan.
-- ═══════════════════════════════════════════════════════════════════════
-- 140 · EHC tahap 1 — klaim EHC jadi PEMAKAIAN SALDO per SP
--       (alokasi ke banyak SP, untuk apa, cara bayar, lampiran wajib,
--        periode cutoff tgl 18, ubah/batal sebelum cutoff #61)
--
-- Keputusan Hannes 6 Okt 2026 (HANDOFF.md "Sesi EHC & komisi"):
--   · EHC yang disisihkan di SP = SALDO. Boleh dipakai berkali-kali lintas
--     bulan selama komisi SP itu belum diklaim; satu transaksi boleh memotong
--     beberapa SP (tiap SP paling banyak sisa saldonya). Komisi diklaim → EHC
--     SP tertutup, sisanya masuk kas sales.
--   · Tiap pemakaian: untuk apa (transfer ke customer / entertain / bongkar
--     muat), cara bayar (transfer langsung ke customer / sales bayar dulu →
--     reimburse; kartu kredit perusahaan menyusul di tahap 2 lewat statement
--     finance), customer penerima, LAMPIRAN WAJIB (mengubah ATURAN B "klaim EHC
--     tidak memerlukan lampiran").
--   · Customer penerima ≠ customer SP → wajib persetujuan GM (ditandai
--     lintas_customer; diputus di tahap 3).
--   · Periode EHC: tgl 19 bulan lalu s.d. tgl 18 bulan ini (WIB). Sebelum
--     cutoff klaim masih bisa diubah/dibatalkan (#61); sesudahnya GM memeriksa,
--     finance memproses tgl 20 (tahap 3).
--   · Klaim boleh dibuat sebelum SP lunas; uangnya (transfer/reimburse) baru
--     keluar sesudah SEMUA SP alokasinya lunas.
--
-- Bentuk: ehc_klaim tetap jadi tabel klaim (id lama tetap → transfer_pengajuan,
-- transfer_batch, ehc_cepat_log, audit tetap sah); alokasi per SP di tabel baru
-- ehc_klaim_alokasi. Saldo per SP = view ehc_saldo_sp; kas sales dihitung
-- ulang dari SP yang tertutup.
--
-- Yang butuh DROP (indeks unik 1 klaim per SP, CHECK cara bayar lama) ada di
-- 140b — DROP lewat MCP Supabase macet, jadi 140b dijalankan manual di SQL
-- Editor. Sebelum 140b jalan, DB hanya lebih ketat (klaim kedua per SP ditolak).
--
-- Data yang diubah: ehc_klaim lama diisi keperluan='uang_customer',
--   customer_id = customer SP, periode = bulan tanggal klaim, status
--   ('disetujui' bila sudah ber-batch, selain itu 'diajukan'); satu baris
--   alokasi per klaim lama bernominal > 0. DEV: klaim #6 (SP 41, Rp 5.000) dan
--   #7 (SP 35, Rp 20.000). Kolom ehc_klaim_nilai.kas tidak diubah (tidak dibaca
--   lagi). Angka EHC per SP tidak berubah.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1. tanggal WIB & periode ─────────────────────────────────────────────
-- DB berjalan di UTC; cutoff EHC dihitung menurut tanggal Jakarta.
create or replace function public.hari_ini_wib()
returns date language sql stable set search_path = public as $$
  select (now() at time zone 'Asia/Jakarta')::date
$$;

-- tgl 1–18 → periode bulan itu; tgl 19–akhir → periode bulan berikutnya.
create or replace function public.periode_ehc(p_tgl date)
returns text language sql immutable set search_path = public as $$
  select to_char(case when extract(day from p_tgl) <= 18 then p_tgl
                      else (date_trunc('month', p_tgl) + interval '1 month')::date end,
                 'YYYY-MM')
$$;

create or replace function public.cutoff_ehc(p_periode text)
returns date language sql immutable set search_path = public as $$
  select to_date(p_periode || '-18', 'YYYY-MM-DD')
$$;

revoke all on function public.hari_ini_wib()        from public, anon;
revoke all on function public.periode_ehc(date)     from public, anon;
revoke all on function public.cutoff_ehc(text)      from public, anon;
grant execute on function public.hari_ini_wib()     to authenticated;
grant execute on function public.periode_ehc(date)  to authenticated;
grant execute on function public.cutoff_ehc(text)   to authenticated;

-- ── 2. kolom baru ehc_klaim ──────────────────────────────────────────────
alter table public.ehc_klaim
  add column if not exists keperluan       text,
  add column if not exists customer_id     bigint references public.customers(id),
  add column if not exists keterangan      text,
  add column if not exists periode         text,
  add column if not exists status          text not null default 'diajukan',
  add column if not exists lintas_customer boolean not null default false,
  add column if not exists batal_alasan    text,
  add column if not exists batal_oleh      uuid references auth.users(id),
  add column if not exists batal_pada      timestamptz,
  add column if not exists diubah_oleh     uuid references auth.users(id),
  add column if not exists diubah_pada     timestamptz;

comment on column public.ehc_klaim.so_id is
  'SP utama = SP alokasi pertama (berkas 140). Rincian per SP ada di ehc_klaim_alokasi.';
comment on column public.ehc_klaim.tanggal is 'Tanggal transaksi (diisi sales, ≤ hari ini WIB).';
comment on column public.ehc_klaim.keperluan is
  'Untuk apa: uang_customer (transfer ke customer) / entertain / bongkar_muat (berkas 140).';
comment on column public.ehc_klaim.customer_id is
  'Customer penerima / yang di-entertain. Beda dengan customer SP alokasi → lintas_customer (butuh GM).';
comment on column public.ehc_klaim.periode is
  'Periode EHC YYYY-MM dari tanggal klaim dibuat (WIB, cutoff tgl 18). Diisi sistem, tidak berubah saat diedit.';
comment on column public.ehc_klaim.status is
  'diajukan / disetujui / ditolak / batal. Batal & ditolak tidak memakai saldo SP.';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ehck_keperluan_sah') then
    alter table public.ehc_klaim add constraint ehck_keperluan_sah
      check (keperluan is null or keperluan in ('uang_customer','entertain','bongkar_muat'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_status_sah') then
    alter table public.ehc_klaim add constraint ehck_status_sah
      check (status in ('diajukan','disetujui','ditolak','batal'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_periode_sah') then
    alter table public.ehc_klaim add constraint ehck_periode_sah
      check (periode is null or periode ~ '^\d{4}-\d{2}$');
  end if;
  -- Cara bayar baru. CHECK lama (transfer|tunai) di-DROP di 140b; sampai saat
  -- itu keduanya berlaku dan 'reimburse' masih ditolak.
  if not exists (select 1 from pg_constraint where conname = 'ehck_cara_bayar_sah2') then
    alter table public.ehc_klaim add constraint ehck_cara_bayar_sah2
      check (cara_bayar in ('transfer','tunai','reimburse','kartu_kredit'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'ehck_batal_beralasan') then
    alter table public.ehc_klaim add constraint ehck_batal_beralasan
      check (status <> 'batal' or coalesce(btrim(batal_alasan), '') <> '');
  end if;
end $$;

create index if not exists ehck_status_periode_idx on public.ehc_klaim (status, periode);

-- ── 3. alokasi per SP ────────────────────────────────────────────────────
create table if not exists public.ehc_klaim_alokasi (
  id       bigserial primary key,
  klaim_id bigint not null references public.ehc_klaim(id) on delete cascade,
  so_id    bigint not null references public.sales_orders(id),
  nominal  numeric(14,2) not null check (nominal > 0),
  constraint ekal_klaim_so_uniq unique (klaim_id, so_id)
);
create index if not exists ekal_so_idx on public.ehc_klaim_alokasi (so_id);
comment on table public.ehc_klaim_alokasi is
  'Bagian satu klaim EHC yang memotong saldo EHC tiap SP (berkas 140). Diisi hanya lewat simpan_klaim_ehc().';

alter table public.ehc_klaim_alokasi enable row level security;
revoke all on public.ehc_klaim_alokasi from public, anon;
grant select on public.ehc_klaim_alokasi to authenticated;
revoke all on sequence public.ehc_klaim_alokasi_id_seq from public, anon;

create policy ekal_baca on public.ehc_klaim_alokasi for select to authenticated
  using (public.boleh_lihat_nilai_klaim() or public.klaim_ehc_saya(klaim_id));

create or replace trigger zz_audit_ehc_klaim_alokasi
  after insert or update or delete on public.ehc_klaim_alokasi
  for each row execute function public.catat_perubahan();

-- ── 4. riwayat klaim (ajukan / ubah / batal) ─────────────────────────────
create table if not exists public.ehc_klaim_log (
  id       bigserial primary key,
  klaim_id bigint not null references public.ehc_klaim(id) on delete cascade,
  aksi     text not null check (aksi in ('ajukan','ubah','batal')),
  catatan  text,
  data     jsonb,
  oleh     uuid references auth.users(id),
  pada     timestamptz not null default now()
);
create index if not exists ekl_klaim_idx on public.ehc_klaim_log (klaim_id, id desc);
alter table public.ehc_klaim_log enable row level security;
revoke all on public.ehc_klaim_log from public, anon;
grant select on public.ehc_klaim_log to authenticated;
revoke all on sequence public.ehc_klaim_log_id_seq from public, anon;
create policy ekl_baca on public.ehc_klaim_log for select to authenticated
  using (public.boleh_lihat_semua_jual() or public.klaim_ehc_saya(klaim_id));

-- ── 5. lampiran: satu berkas hanya untuk satu klaim; diaudit ─────────────
create unique index if not exists ekb_path_uniq on public.ehc_klaim_berkas (path);
create or replace trigger zz_audit_ehc_klaim_berkas
  after insert or update or delete on public.ehc_klaim_berkas
  for each row execute function public.catat_perubahan();

-- ── 6. nominal hanya lewat RPC ───────────────────────────────────────────
-- Dulu staff/finance/GM/owner bisa PATCH ehc_klaim_nilai lewat REST; dengan
-- alokasi, nominal yang diubah sendirian tidak lagi sama dengan jumlah
-- alokasinya. Fungsi SECURITY DEFINER tetap bisa menulis (RLS tidak dipaksa).
alter policy ekn_ubah   on public.ehc_klaim_nilai using (false) with check (false);
alter policy ekn_tambah on public.ehc_klaim_nilai with check (false);

-- ── 7. konversi klaim lama ───────────────────────────────────────────────
update public.ehc_klaim k
   set keperluan   = 'uang_customer',
       customer_id = s.customer_id,
       periode     = to_char(k.tanggal, 'YYYY-MM'),
       status      = case when k.transfer_batch_id is not null then 'disetujui' else 'diajukan' end
  from public.sales_orders s
 where s.id = k.so_id and k.keperluan is null;

insert into public.ehc_klaim_alokasi (klaim_id, so_id, nominal)
select k.id, k.so_id, n.nominal
  from public.ehc_klaim k
  join public.ehc_klaim_nilai n on n.klaim_id = k.id
 where n.nominal > 0
   and not exists (select 1 from public.ehc_klaim_alokasi a where a.klaim_id = k.id);

-- Sesudah konversi, setiap klaim punya keperluan & periode.
alter table public.ehc_klaim alter column keperluan set not null;
alter table public.ehc_klaim alter column periode   set not null;

-- ── 8. saldo EHC per SP ──────────────────────────────────────────────────
-- total_ehc = EHC SP dalam DPP (so_ringkas; mode include ÷ 1,11), DIPOTONG ke
-- sen di bawahnya — saldo tidak pernah dibulatkan ke atas. Terpakai = alokasi
-- dari klaim yang diajukan/disetujui. Tertutup = komisi SP sudah diklaim.
create or replace view public.ehc_saldo_sp with (security_invoker = on) as
select s.id                                   as so_id,
       s.no_sp,
       s.tanggal,
       s.kepada,
       s.customer_id,
       c.nama                                 as customer,
       s.sales_rep_id,
       s.lunas,
       s.tgl_lunas,
       trunc(coalesce(r.total_ehc, 0), 2)     as total_ehc,
       coalesce(a.terpakai, 0)                as terpakai,
       trunc(coalesce(r.total_ehc, 0), 2) - coalesce(a.terpakai, 0) as sisa,
       coalesce(a.jumlah_klaim, 0)            as jumlah_klaim,
       exists (select 1 from public.komisi_klaim kk where kk.so_id = s.id) as tertutup
  from public.sales_orders s
  left join public.so_ringkas r on r.so_id = s.id
  left join public.customers  c on c.id = s.customer_id
  left join lateral (
    select sum(x.nominal) as terpakai, count(distinct x.klaim_id) as jumlah_klaim
      from public.ehc_klaim_alokasi x
      join public.ehc_klaim k on k.id = x.klaim_id
     where x.so_id = s.id and k.status in ('diajukan','disetujui')
  ) a on true
 where not s.batal;
revoke all on public.ehc_saldo_sp from public, anon;
grant select on public.ehc_saldo_sp to authenticated;

-- Kas sales = sisa EHC dari SP yang komisinya sudah diklaim. Kolom lama
-- dipertahankan; jumlah_klaim kini = jumlah SP penyumbang.
create or replace view public.kas_sales with (security_invoker = on) as
select v.sales_rep_id,
       r.nama          as sales,
       sum(v.sisa)     as saldo,
       count(*)        as jumlah_klaim
  from public.ehc_saldo_sp v
  left join public.sales_reps r on r.id = v.sales_rep_id
 where v.tertutup and v.sisa > 0
 group by v.sales_rep_id, r.nama;
revoke all on public.kas_sales from anon;

-- ── 9. gerbang insert klaim ──────────────────────────────────────────────
-- Syarat "SP lunas atau dini disetujui GM" DIHAPUS: klaim boleh dibuat sebelum
-- lunas (entertain bisa lebih dulu). Uang baru keluar sesudah SP lunas —
-- dijaga di jalur pembayaran (ajukan_transfer di bawah, lalu tahap 3).
create or replace function public.jaga_gerbang_klaim()
returns trigger language plpgsql security definer set search_path = public as $$
declare s public.sales_orders;
begin
  select * into s from public.sales_orders where id = new.so_id;
  if not found then raise exception 'Surat Pesanan tidak ditemukan.'; end if;
  new.sales_rep_id := coalesce(new.sales_rep_id, s.sales_rep_id);
  new.dibuat_oleh  := auth.uid();
  return new;
end $$;

-- ── 10. saldo EHC SP tidak boleh minus ───────────────────────────────────
-- Dicek saat COMMIT (constraint trigger tertunda), sehingga perubahan banyak
-- baris dalam satu transaksi dinilai hasil akhirnya.
create or replace function public.jaga_saldo_ehc_sp()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_so bigint; v_terpakai numeric; v_total numeric; v_batal boolean; v_no text;
begin
  if TG_TABLE_NAME = 'sales_order_lines' then
    v_so := case when TG_OP = 'DELETE' then old.so_id else new.so_id end;
  else
    v_so := new.id;
  end if;
  select coalesce(sum(a.nominal), 0) into v_terpakai
    from public.ehc_klaim_alokasi a join public.ehc_klaim k on k.id = a.klaim_id
   where a.so_id = v_so and k.status in ('diajukan','disetujui');
  if v_terpakai = 0 then return null; end if;

  select s.batal, s.no_sp into v_batal, v_no from public.sales_orders s where s.id = v_so;
  if not found then return null; end if;
  if v_batal then
    raise exception 'SP % tidak bisa dibatalkan: EHC-nya sudah dipakai % lewat klaim EHC yang masih aktif. '
                    'Batalkan klaim EHC-nya dulu (sebelum cutoff) atau minta GM menolaknya.',
                    v_no, public.rp_teks(v_terpakai) using errcode = '23514';
  end if;
  select trunc(coalesce(r.total_ehc, 0), 2) into v_total from public.so_ringkas r where r.so_id = v_so;
  if coalesce(v_total, 0) < v_terpakai then
    raise exception 'EHC SP % tinggal % sesudah perubahan ini, padahal klaim EHC aktif atas SP ini sudah %. '
                    'Ubah atau batalkan klaim EHC-nya dulu.',
                    v_no, public.rp_teks(coalesce(v_total, 0)), public.rp_teks(v_terpakai)
      using errcode = '23514';
  end if;
  return null;
end $$;
revoke all on function public.jaga_saldo_ehc_sp() from public, anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'sol_jaga_saldo_ehc') then
    create constraint trigger sol_jaga_saldo_ehc
      after insert or update or delete on public.sales_order_lines
      deferrable initially deferred
      for each row execute function public.jaga_saldo_ehc_sp();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'so_jaga_saldo_ehc') then
    create constraint trigger so_jaga_saldo_ehc
      after update of batal, mode_ppn, ppn_kena on public.sales_orders
      deferrable initially deferred
      for each row execute function public.jaga_saldo_ehc_sp();
  end if;
end $$;

-- SP yang pernah dipakai klaim EHC tidak dihapus diam-diam: FK ehc_klaim.so_id
-- (CASCADE, lama) akan ikut menghapus klaim beserta alokasinya ke SP lain.
create or replace function public.jaga_hapus_sp_ehc()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.ehc_klaim_alokasi where so_id = old.id)
     or exists (select 1 from public.ehc_klaim where so_id = old.id) then
    raise exception 'SP % tidak bisa dihapus: sudah ada klaim EHC atas SP ini. Batalkan SP-nya saja '
                    '(setelah klaim EHC-nya dibatalkan) supaya riwayat klaimnya tetap ada.', old.no_sp
      using errcode = '23503';
  end if;
  return old;
end $$;
revoke all on function public.jaga_hapus_sp_ehc() from public, anon, authenticated;
create or replace trigger so_jaga_hapus_ehc
  before delete on public.sales_orders
  for each row execute function public.jaga_hapus_sp_ehc();

-- ── 11. simpan klaim EHC (baru atau ubah) ────────────────────────────────
create or replace function public.simpan_klaim_ehc(p_klaim bigint, p_data jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_peran text := public.peran_saya();
  v_hari  date := public.hari_ini_wib();
  k       public.ehc_klaim;
  v_baru  boolean := p_klaim is null;
  v_id    bigint;
  v_kep   text := lower(btrim(coalesce(p_data->>'keperluan', '')));
  v_cara  text := lower(btrim(coalesce(p_data->>'cara_bayar', '')));
  v_tgl   date;
  v_cust  bigint;
  v_pic   public.customer_pics;
  v_ket   text := nullif(btrim(coalesce(p_data->>'keterangan', '')), '');
  v_alas  text := nullif(btrim(coalesce(p_data->>'cepat_alasan', '')), '');
  v_rep   bigint;
  v_utama bigint;
  v_total numeric(14,2) := 0;
  v_lintas boolean := false;
  v_n     integer;
  v_sisa  numeric;
  a       record;
  s       record;
  b       jsonb;
  v_path  text;
begin
  -- 1 · peran
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengajukan atau mengubah klaim EHC.' using errcode = '42501';
  end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'Isi klaim tidak terbaca.' using errcode = '22023';
  end if;

  -- 2 · klaim lama (ubah)
  if not v_baru then
    select * into k from public.ehc_klaim where id = p_klaim for update;
    if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
    if not (public.klaim_ehc_saya(p_klaim) or v_peran in ('owner','gm','staff')) then
      raise exception 'Klaim EHC ini bukan milik Anda.' using errcode = '42501';
    end if;
    if k.status <> 'diajukan' then
      raise exception 'Klaim EHC ini berstatus %, tidak bisa diubah lagi.', k.status using errcode = '22023';
    end if;
    if k.transfer_batch_id is not null then
      raise exception 'Klaim EHC ini sudah ditransfer (batch #%).', k.transfer_batch_id using errcode = '22023';
    end if;
    if public.klaim_ehc_terkunci_pengajuan(p_klaim) is not null then
      raise exception 'Klaim EHC ini sudah masuk pengajuan transfer, tidak bisa diubah.' using errcode = '22023';
    end if;
    if k.cepat_minta and k.cepat_ok is distinct from false then
      raise exception 'Klaim ini sedang/sudah diajukan sebagai EHC cepat. Tarik permintaan cepatnya dulu '
                      'kalau masih menunggu GM.' using errcode = '22023';
    end if;
    if v_hari > public.cutoff_ehc(k.periode) then
      raise exception 'Periode % sudah lewat cutoff (%). Klaim ini sudah terkunci untuk diperiksa GM.',
                      k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
    end if;
  end if;

  -- 3 · untuk apa & cara bayar
  if v_kep not in ('uang_customer','entertain','bongkar_muat') then
    raise exception 'Pilih untuk apa EHC ini dipakai: transfer ke customer, entertain, atau bongkar muat.'
      using errcode = '22023';
  end if;
  if v_cara = 'kartu_kredit' then
    raise exception 'Pemakaian kartu kredit perusahaan dicatat lewat statement dari finance (menyusul), '
                    'bukan dari form ini.' using errcode = '22023';
  end if;
  if v_cara not in ('transfer','reimburse') then
    raise exception 'Pilih cara bayar: transfer langsung ke customer, atau sales bayar dulu (reimburse).'
      using errcode = '22023';
  end if;

  -- 4 · tanggal transaksi
  begin
    v_tgl := (p_data->>'tanggal')::date;
  exception when others then
    raise exception 'Tanggal transaksi tidak terbaca.' using errcode = '22023';
  end;
  if v_tgl is null then raise exception 'Tanggal transaksi wajib diisi.' using errcode = '22023'; end if;
  if v_tgl > v_hari then
    raise exception 'Tanggal transaksi tidak boleh di masa depan.' using errcode = '22023';
  end if;

  -- 5 · customer penerima
  begin
    v_cust := (p_data->>'customer_id')::bigint;
  exception when others then v_cust := null; end;
  if v_cust is null or not exists (select 1 from public.customers where id = v_cust) then
    raise exception 'Pilih customer penerima / yang di-entertain.' using errcode = '22023';
  end if;
  if not public.pic_pelanggan_saya(v_cust) then
    raise exception 'Customer itu dipegang sales lain. EHC tidak bisa dipakai untuk pelanggan sales lain.'
      using errcode = '42501';
  end if;

  -- 6 · alokasi
  if jsonb_typeof(p_data->'alokasi') is distinct from 'array' or jsonb_array_length(p_data->'alokasi') = 0 then
    raise exception 'Pilih minimal satu SP yang saldo EHC-nya dipakai.' using errcode = '22023';
  end if;
  create temp table if not exists _ehc_alok (urut int, so_id bigint, nominal numeric) on commit drop;
  delete from _ehc_alok;
  begin
    insert into _ehc_alok (urut, so_id, nominal)
    select x.ord::int, (x.v->>'so_id')::bigint, (x.v->>'nominal')::numeric
      from jsonb_array_elements(p_data->'alokasi') with ordinality as x(v, ord);
  exception when others then
    raise exception 'Daftar SP dan nominal tidak terbaca.' using errcode = '22023';
  end;
  if exists (select 1 from _ehc_alok where so_id is null or nominal is null) then
    raise exception 'Setiap SP wajib punya nominal.' using errcode = '22023';
  end if;
  if exists (select 1 from _ehc_alok where nominal <= 0 or nominal <> trunc(nominal, 2)) then
    raise exception 'Nominal per SP harus lebih dari nol dan paling banyak dua angka di belakang koma (sen).'
      using errcode = '22023';
  end if;
  if (select count(*) from _ehc_alok) <> (select count(distinct so_id) from _ehc_alok) then
    raise exception 'SP yang sama dipilih dua kali.' using errcode = '22023';
  end if;

  -- kunci SP (urut id) supaya dua klaim bersamaan tidak sama-sama lolos cek saldo
  perform 1 from public.sales_orders where id in (select so_id from _ehc_alok) order by id for update;

  for a in select * from _ehc_alok order by urut loop
    select so.id, so.no_sp, so.batal, so.sales_rep_id, so.customer_id
      into s from public.sales_orders so where so.id = a.so_id;
    if not found then raise exception 'SP #% tidak ditemukan.', a.so_id using errcode = 'P0002'; end if;
    if not public.boleh_lihat_sp(a.so_id) then
      raise exception 'SP % bukan milik Anda. Saldo EHC hanya bisa dipakai dari SP yang Anda pegang.', s.no_sp
        using errcode = '42501';
    end if;
    if s.batal then raise exception 'SP % sudah dibatalkan.', s.no_sp using errcode = '22023'; end if;
    if s.sales_rep_id is null then
      raise exception 'SP % belum punya sales.', s.no_sp using errcode = '22023';
    end if;
    if v_rep is null then v_rep := s.sales_rep_id; v_utama := s.id;
    elsif v_rep <> s.sales_rep_id then
      raise exception 'Semua SP dalam satu klaim EHC harus milik sales yang sama.' using errcode = '22023';
    end if;
    if exists (select 1 from public.komisi_klaim kk where kk.so_id = a.so_id) then
      raise exception 'Komisi SP % sudah diklaim — EHC-nya sudah tertutup dan sisanya masuk kas sales.', s.no_sp
        using errcode = '22023';
    end if;
    select trunc(coalesce(r.total_ehc, 0), 2)
           - coalesce((select sum(x.nominal) from public.ehc_klaim_alokasi x
                         join public.ehc_klaim kx on kx.id = x.klaim_id
                        where x.so_id = a.so_id and kx.status in ('diajukan','disetujui')
                          and kx.id is distinct from p_klaim), 0)
      into v_sisa
      from public.sales_orders so left join public.so_ringkas r on r.so_id = so.id
     where so.id = a.so_id;
    if a.nominal > coalesce(v_sisa, 0) then
      raise exception 'Saldo EHC SP % tinggal %, tidak cukup untuk %.',
                      s.no_sp, public.rp_teks(greatest(coalesce(v_sisa, 0), 0)), public.rp_teks(a.nominal)
        using errcode = '22023';
    end if;
    if s.customer_id is distinct from v_cust then v_lintas := true; end if;
    v_total := v_total + a.nominal;
  end loop;

  -- 8 · rekening tujuan
  if v_cara = 'transfer' then
    begin
      select * into v_pic from public.customer_pics where id = (p_data->>'pic_id')::bigint;
    exception when others then v_pic := null; end;
    if v_pic.id is null then
      raise exception 'Pilih PIC penerima transfer.' using errcode = '22023';
    end if;
    if v_pic.customer_id is distinct from v_cust then
      raise exception 'PIC % bukan PIC customer penerima.', v_pic.nama using errcode = '42501';
    end if;
    if not coalesce(v_pic.aktif, true) then
      raise exception 'PIC % sudah tidak aktif.', v_pic.nama using errcode = '22023';
    end if;
    if coalesce(btrim(v_pic.bank), '') = '' or coalesce(btrim(v_pic.no_rekening), '') = '' then
      raise exception 'PIC % belum punya rekening. Isi rekeningnya dulu.', v_pic.nama using errcode = '22023';
    end if;
  end if;

  -- 9 · lampiran
  if p_data ? 'berkas' and jsonb_typeof(p_data->'berkas') <> 'array' then
    raise exception 'Daftar lampiran tidak berbentuk daftar.' using errcode = '22023';
  end if;
  for b in select * from jsonb_array_elements(coalesce(p_data->'berkas', '[]'::jsonb)) loop
    v_path := btrim(coalesce(b->>'path', ''));
    if coalesce(btrim(b->>'nama_berkas'), '') = '' or v_path = '' then
      raise exception 'Ada lampiran yang tidak punya nama berkas atau alamat penyimpanan.' using errcode = '22023';
    end if;
    if v_path not like 'ehc/%' then
      raise exception 'Lampiran % tidak berada di folder bukti EHC.', b->>'nama_berkas' using errcode = '42501';
    end if;
    if not exists (select 1 from storage.objects o
                    where o.bucket_id = 'dokumen' and o.name = v_path
                      and (o.owner = auth.uid() or o.owner_id = auth.uid()::text)) then
      raise exception 'Lampiran % tidak ditemukan atau bukan unggahan Anda. Unggah ulang berkasnya.',
                      b->>'nama_berkas' using errcode = '42501';
    end if;
    if exists (select 1 from public.ehc_klaim_berkas f where f.path = v_path) then
      raise exception 'Lampiran % sudah dipakai klaim lain.', b->>'nama_berkas' using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(p_data->'berkas_hapus') = 'array' and v_baru then
    raise exception 'Klaim baru tidak punya lampiran untuk dibuang.' using errcode = '22023';
  end if;

  -- 10 · simpan
  if v_baru then
    perform set_config('rhj.klaim_ehc', 'on', true);
    insert into public.ehc_klaim (so_id, pic_id, bank, no_rekening, atas_nama, dini, tanggal, cara_bayar,
                                  keperluan, customer_id, keterangan, periode, status, lintas_customer,
                                  sales_rep_id)
    values (v_utama,
            case when v_cara = 'transfer' then v_pic.id end,
            case when v_cara = 'transfer' then v_pic.bank end,
            case when v_cara = 'transfer' then v_pic.no_rekening end,
            case when v_cara = 'transfer' then v_pic.atas_nama end,
            false, v_tgl, v_cara, v_kep, v_cust, v_ket, public.periode_ehc(v_hari), 'diajukan', v_lintas,
            v_rep)
    returning id into v_id;
    perform set_config('rhj.klaim_ehc', 'off', true);
    insert into public.ehc_klaim_nilai (klaim_id, nominal, kas) values (v_id, v_total, 0);
  else
    v_id := p_klaim;
    insert into public.ehc_klaim_log (klaim_id, aksi, data, oleh)
    values (v_id, 'ubah',
            jsonb_build_object('klaim', to_jsonb(k),
              'nominal', (select n.nominal from public.ehc_klaim_nilai n where n.klaim_id = v_id),
              'alokasi', (select coalesce(jsonb_agg(jsonb_build_object('so_id', x.so_id, 'nominal', x.nominal)
                                                     order by x.id), '[]'::jsonb)
                            from public.ehc_klaim_alokasi x where x.klaim_id = v_id)),
            auth.uid());
    update public.ehc_klaim
       set so_id = v_utama,
           pic_id      = case when v_cara = 'transfer' then v_pic.id end,
           bank        = case when v_cara = 'transfer' then v_pic.bank end,
           no_rekening = case when v_cara = 'transfer' then v_pic.no_rekening end,
           atas_nama   = case when v_cara = 'transfer' then v_pic.atas_nama end,
           tanggal = v_tgl, cara_bayar = v_cara, keperluan = v_kep, customer_id = v_cust,
           keterangan = v_ket, lintas_customer = v_lintas, sales_rep_id = v_rep,
           diubah_oleh = auth.uid(), diubah_pada = now()
     where id = v_id;
    update public.ehc_klaim_nilai set nominal = v_total, kas = 0 where klaim_id = v_id;
    delete from public.ehc_klaim_alokasi where klaim_id = v_id;
    if jsonb_typeof(p_data->'berkas_hapus') = 'array' then
      delete from public.ehc_klaim_berkas f
       where f.klaim_id = v_id
         and f.id in (select (x)::bigint from jsonb_array_elements_text(p_data->'berkas_hapus') x);
    end if;
  end if;

  insert into public.ehc_klaim_alokasi (klaim_id, so_id, nominal)
  select v_id, so_id, nominal from _ehc_alok order by urut;

  insert into public.ehc_klaim_berkas (klaim_id, nama_berkas, path, ukuran, mime, dibuat_oleh)
  select v_id, btrim(x->>'nama_berkas'), btrim(x->>'path'),
         nullif(x->>'ukuran', '')::bigint, nullif(btrim(x->>'mime'), ''), auth.uid()
    from jsonb_array_elements(coalesce(p_data->'berkas', '[]'::jsonb)) x;

  select count(*) into v_n from public.ehc_klaim_berkas where klaim_id = v_id;
  if v_n = 0 then
    raise exception 'Lampiran wajib: lampirkan bill/nota atau bukti transfer.' using errcode = '22023';
  end if;

  if v_baru then
    insert into public.ehc_klaim_log (klaim_id, aksi, oleh) values (v_id, 'ajukan', auth.uid());
    if v_alas is not null then
      perform public.minta_klaim_cepat(v_id, v_alas);
    end if;
  end if;
  return v_id;
end $$;
revoke all on function public.simpan_klaim_ehc(bigint, jsonb) from public, anon;
grant execute on function public.simpan_klaim_ehc(bigint, jsonb) to authenticated;

-- ── 12. batalkan klaim EHC sebelum cutoff (#61) ──────────────────────────
create or replace function public.batalkan_klaim_ehc(p_klaim bigint, p_alasan text)
returns text language plpgsql security definer set search_path = public as $$
declare k public.ehc_klaim; v_alasan text := nullif(btrim(coalesce(p_alasan, '')), '');
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak membatalkan klaim EHC.' using errcode = '42501';
  end if;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if not (public.klaim_ehc_saya(p_klaim) or public.peran_saya() in ('owner','gm','staff')) then
    raise exception 'Klaim EHC ini bukan milik Anda.' using errcode = '42501';
  end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC ini berstatus %, tidak bisa dibatalkan.', k.status using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim EHC ini sudah ditransfer (batch #%).', k.transfer_batch_id using errcode = '22023';
  end if;
  if public.klaim_ehc_terkunci_pengajuan(p_klaim) is not null then
    raise exception 'Klaim EHC ini sudah masuk pengajuan transfer, tidak bisa dibatalkan.' using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is distinct from false then
    raise exception 'Klaim ini sedang/sudah diajukan sebagai EHC cepat. Tarik permintaan cepatnya dulu '
                    'kalau masih menunggu GM.' using errcode = '22023';
  end if;
  if public.hari_ini_wib() > public.cutoff_ehc(k.periode) then
    raise exception 'Periode % sudah lewat cutoff (%). Klaim ini menunggu pemeriksaan GM.',
                    k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
  end if;
  if v_alasan is null then
    raise exception 'Alasan pembatalan wajib diisi.' using errcode = '22023';
  end if;
  update public.ehc_klaim
     set status = 'batal', batal_alasan = v_alasan, batal_oleh = auth.uid(), batal_pada = now()
   where id = p_klaim;
  insert into public.ehc_klaim_log (klaim_id, aksi, catatan, oleh) values (p_klaim, 'batal', v_alasan, auth.uid());
  return 'Klaim EHC dibatalkan. Saldo EHC SP-nya kembali dan bisa dipakai lagi.';
end $$;
revoke all on function public.batalkan_klaim_ehc(bigint, text) from public, anon;
grant execute on function public.batalkan_klaim_ehc(bigint, text) to authenticated;

-- ── 13. jalur lama dipensiunkan ──────────────────────────────────────────
-- Tidak di-DROP (macet lewat MCP) — badannya diganti penolakan, supaya tidak
-- ada jalan memintas lampiran wajib & cek saldo.
create or replace function public.ajukan_klaim_ehc(p_so bigint, p_pic bigint, p_nominal numeric,
                                                   p_tanggal date, p_berkas jsonb, p_cara_bayar text)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Klaim EHC sekarang diajukan lewat form baru (simpan_klaim_ehc): bisa memakai beberapa SP, '
                  'wajib lampiran. Muat ulang halaman.' using errcode = '0A000';
end $$;
create or replace function public.ajukan_klaim_ehc_cepat(p_so bigint, p_pic bigint, p_nominal numeric,
                                                         p_tanggal date, p_berkas jsonb, p_cara_bayar text,
                                                         p_alasan text)
returns bigint language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Klaim EHC cepat sekarang diajukan lewat form baru (simpan_klaim_ehc dengan alasan '
                  'mendesak). Muat ulang halaman.' using errcode = '0A000';
end $$;

-- ── 14. EHC cepat: hanya klaim yang masih diajukan ───────────────────────
create or replace function public.minta_klaim_cepat(p_klaim bigint, p_alasan text)
returns text language plpgsql security definer set search_path = public as $$
declare k public.ehc_klaim; v_alasan text; v_pj bigint; v_sp text;
begin
  v_alasan := nullif(btrim(coalesce(p_alasan, '')), '');

  select * into k from public.ehc_klaim where id = p_klaim;
  if not found then
    raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002';
  end if;
  if not public.boleh_minta_klaim_cepat(p_klaim) then
    raise exception 'Anda tidak berhak mengajukan pencairan cepat untuk klaim ini.'
      using errcode = '42501';
  end if;
  -- berkas 140: klaim yang batal/ditolak/sudah disetujui tidak bisa dipercepat.
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC ini berstatus % — hanya klaim yang masih diajukan yang bisa dipercepat.',
                    k.status using errcode = '22023';
  end if;

  if v_alasan is null then
    raise exception 'Alasan mendesak wajib diisi — GM tidak bisa memutuskan pencairan di '
                    'luar jadwal tanpa tahu apa yang mendesak.' using errcode = '22023';
  end if;
  if length(v_alasan) < 10 then
    raise exception 'Alasan mendesak terlalu pendek (% huruf). Tulis apa yang mendesak dan '
                    'kapan uangnya dibutuhkan — GM memutuskan dari kalimat ini.',
                    length(v_alasan) using errcode = '22023';
  end if;

  if k.transfer_batch_id is not null then
    raise exception 'Klaim ini sudah ditransfer lewat batch #% — tidak ada yang perlu '
                    'dipercepat lagi.', k.transfer_batch_id using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is null then
    raise exception 'Klaim ini sudah diajukan sebagai klaim cepat dan masih menunggu GM. '
                    'Tarik dulu kalau alasannya mau diperbaiki.' using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok then
    raise exception 'Klaim ini sudah DISETUJUI GM untuk dicairkan cepat. Yang ditunggu '
                    'sekarang finance, bukan GM.' using errcode = '22023';
  end if;

  v_pj := public.klaim_ehc_terkunci_pengajuan(p_klaim);
  if v_pj is not null then
    raise exception
      'Klaim ini sudah terkunci di pengajuan transfer bulanan #% yang belum selesai. '
      'Kalau memang harus didahulukan, finance menarik dulu pengajuan itu '
      '(tarik_pengajuan_transfer), baru klaim ini diajukan sebagai klaim cepat — '
      'kalau tidak, GM menyetujui satu daftar dan yang terbayar isinya lain.', v_pj
      using errcode = '22023';
  end if;

  perform set_config('rhj.cepat', 'on', true);
  update public.ehc_klaim
     set cepat_minta = true, cepat_ok = null, cepat_alasan = v_alasan, cepat_catatan = null,
         cepat_diminta_oleh = auth.uid(), cepat_diminta_pada = now(),
         cepat_diputus_oleh = null, cepat_diputus_pada = null
   where id = p_klaim;
  perform set_config('rhj.cepat', 'off', true);

  insert into public.ehc_cepat_log (klaim_id, aksi, alasan, oleh)
  values (p_klaim, 'minta', v_alasan, auth.uid());

  select no_sp into v_sp from public.sales_orders where id = k.so_id;
  return 'Klaim EHC ' || coalesce(v_sp, '#' || p_klaim) || ' diajukan sebagai KLAIM CEPAT dan '
      || 'masuk antrean GM. Selama menunggu, klaim ini tidak ikut rekap bulanan.';
end $$;

create or replace view public.ehc_cepat_siap with (security_invoker = on) as
select k.id AS klaim_id,
    k.so_id,
    s.no_sp,
    s.kepada,
    k.sales_rep_id,
    r.nama AS sales,
    p.nama AS pic,
    k.cara_bayar,
    k.bank,
    k.no_rekening,
    k.atas_nama,
    k.tanggal,
    n.nominal,
    k.cepat_alasan,
    k.cepat_catatan,
    k.cepat_diputus_pada,
    public.klaim_ehc_terkunci_pengajuan(k.id) AS pengajuan_bulanan
   from public.ehc_klaim k
     left join public.sales_orders s on s.id = k.so_id
     left join public.sales_reps r on r.id = k.sales_rep_id
     left join public.customer_pics p on p.id = k.pic_id
     left join public.ehc_klaim_nilai n on n.klaim_id = k.id
  where k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null and k.status <> 'batal';

-- ── 15. pengajuan transfer EHC (SEMENTARA, sampai tahap 3) ───────────────
-- Cabang 'ehc': periode (bukan bulan tanggal klaim), hanya sesudah cutoff,
-- hanya klaim aktif yang bukan klaim cepat, dan hanya bila SEMUA SP
-- alokasinya sudah lunas. Cabang komisi tidak berubah.
create or replace function public.ajukan_transfer(p_jenis text, p_bulan text, p_catatan text default null::text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_n integer; v_total numeric(14,2); v_lama public.transfer_pengajuan;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengajukan transfer.'
      using errcode = '42501';
  end if;
  if p_jenis not in ('ehc','komisi') then
    raise exception 'Jenis harus ehc atau komisi.' using errcode = '22023';
  end if;
  if p_bulan !~ '^\d{4}-\d{2}$' then
    raise exception 'Bulan harus dalam bentuk YYYY-MM.' using errcode = '22023';
  end if;
  if p_jenis = 'ehc' and public.hari_ini_wib() <= public.cutoff_ehc(p_bulan) then
    raise exception 'Periode EHC % baru ditutup sesudah tanggal %. Sebelum cutoff, sales masih boleh '
                    'mengubah klaimnya.', p_bulan, to_char(public.cutoff_ehc(p_bulan), 'DD-MM-YYYY')
      using errcode = '22023';
  end if;

  select * into v_lama from public.transfer_pengajuan
   where jenis = p_jenis and bulan = p_bulan and status in ('menunggu','disetujui');
  if found then
    return jsonb_build_object('pengajuan', v_lama.id, 'status', v_lama.status,
      'jumlah', v_lama.jumlah_klaim, 'total', v_lama.total,
      'pesan', case when v_lama.status = 'menunggu'
                 then 'Pengajuan #' || v_lama.id || ' untuk ' || p_jenis || ' bulan ' || p_bulan
                      || ' sudah ada dan masih menunggu GM. Tidak ada pengajuan baru yang dibuat.'
                 else 'Pengajuan #' || v_lama.id || ' untuk ' || p_jenis || ' bulan ' || p_bulan
                      || ' SUDAH DISETUJUI GM. Silakan transfer, lalu tandai sudah ditransfer.'
               end);
  end if;

  insert into public.transfer_pengajuan (jenis, bulan, catatan, diajukan_oleh)
  values (p_jenis, p_bulan, nullif(btrim(coalesce(p_catatan,'')), ''), auth.uid())
  returning id into v_id;

  if p_jenis = 'ehc' then
    insert into public.transfer_pengajuan_baris (pengajuan_id, klaim_id)
    select v_id, k.id from public.ehc_klaim k
     where k.transfer_batch_id is null
       and k.status in ('diajukan','disetujui')
       and k.periode = p_bulan
       and k.cara_bayar in ('transfer','reimburse','tunai')
       and not (k.cepat_minta and k.cepat_ok is distinct from false)
       and exists (select 1 from public.ehc_klaim_alokasi a where a.klaim_id = k.id)
       and not exists (select 1 from public.ehc_klaim_alokasi a
                         join public.sales_orders s on s.id = a.so_id
                        where a.klaim_id = k.id and not s.lunas);
    select count(*), coalesce(sum(n.nominal), 0) into v_n, v_total
      from public.transfer_pengajuan_baris b
      join public.ehc_klaim_nilai n on n.klaim_id = b.klaim_id
     where b.pengajuan_id = v_id;
  else
    insert into public.transfer_pengajuan_baris (pengajuan_id, klaim_id)
    select v_id, k.id from public.komisi_klaim k
     where k.transfer_batch_id is null and to_char(k.tanggal, 'YYYY-MM') = p_bulan;
    select count(*), coalesce(sum(n.nominal), 0) into v_n, v_total
      from public.transfer_pengajuan_baris b
      join public.komisi_klaim_nilai n on n.klaim_id = b.klaim_id
     where b.pengajuan_id = v_id;
  end if;

  if v_n = 0 then
    delete from public.transfer_pengajuan where id = v_id;
    return jsonb_build_object('pengajuan', null, 'jumlah', 0, 'total', 0,
      'pesan', 'Tidak ada klaim ' || p_jenis || ' bulan ' || p_bulan
            || ' yang siap ditransfer. Tidak ada yang perlu disetujui.');
  end if;

  update public.transfer_pengajuan
     set jumlah_klaim = v_n, total = v_total where id = v_id;

  return jsonb_build_object('pengajuan', v_id, 'status', 'menunggu',
    'jumlah', v_n, 'total', v_total,
    'pesan', v_n || ' klaim ' || p_jenis || ' bulan ' || p_bulan
          || ' diajukan ke GM sebagai pengajuan #' || v_id
          || '. Daftarnya sudah dikunci — klaim yang masuk sesudah ini menunggu '
          || 'pengajuan berikutnya.');
end $$;
