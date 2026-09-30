-- ═══════════════════════════════════════════════════════════════════════
-- 114 · #30 #42 Mode PPN di PO & SP: Exclude / Include / Non-PPN
--
-- Keputusan Hannes (HANDOFF, disetujui):
--   · Exclude  — harga belum termasuk PPN: grand = Σ baris + 11% × Σ barang (seperti dulu).
--   · Include  — harga SUDAH termasuk PPN: grand = Σ baris PERSIS (qty × harga apa adanya);
--                DPP = Σ barang ÷ 1,11; PPN = Σ barang − DPP. Baris biaya tidak kena PPN.
--   · Non-PPN  — tanpa PPN: grand = Σ baris.
--   · SP mengikuti mode PO-nya.
-- Turunan agar aturan yang sudah ada tidak bergeser (price list, tier komisi, harga khusus,
-- HPP, EHC semuanya dalam angka TANPA PPN): pada mode Include harga nett & EHC per item di SP
-- dibaca termasuk PPN, lalu komisi, tier price list, harga khusus, margin, dan nilai EHC
-- dihitung dari DPP-nya (÷ 1,11). Tanpa ini SP include seharga price list (DPP-nya 10% di
-- bawah list) malah terbaca "≥ list × 1,10" → komisi 5%.
--
-- Kolom baru mode_ppn di purchase_orders & sales_orders; ppn_kena TETAP ada dan selalu
-- = (mode_ppn <> 'non') lewat trigger (klien lama yang hanya mengirim ppn_kena tetap jalan).
-- View diubah dengan kolom lama tetap di tempatnya (kolom baru di ujung) dan security_invoker
-- dipertahankan. Data lama: ppn_kena true → 'exclude', false → 'non' → semua angka lama sama
-- persis (diperiksa dengan sidik md5 sebelum/sesudah). Tidak ada data yang dihapus.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) kolom & isi awal ─────────────────────────────────────────────────
-- DEFAULT 'exclude' saat ADD COLUMN mengisi baris lama tanpa menyalakan trigger; baris
-- non-PPN (ppn_kena false) lalu disetel 'non' dengan trigger baris dimatikan sesaat
-- (hanya mengisi kolom baru, tidak ada angka lain yang tersentuh).
alter table public.purchase_orders add column if not exists mode_ppn text not null default 'exclude';
alter table public.sales_orders    add column if not exists mode_ppn text not null default 'exclude';
alter table public.purchase_orders disable trigger user;
update public.purchase_orders set mode_ppn = 'non' where not ppn_kena and mode_ppn <> 'non';
alter table public.purchase_orders enable trigger user;
alter table public.sales_orders disable trigger user;
update public.sales_orders set mode_ppn = 'non' where not ppn_kena and mode_ppn <> 'non';
alter table public.sales_orders enable trigger user;
-- Tanpa default: INSERT yang tidak menyebut mode_ppn diisi trigger dari ppn_kena (klien lama).
alter table public.purchase_orders alter column mode_ppn drop default;
alter table public.sales_orders    alter column mode_ppn drop default;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'purchase_orders_mode_ppn_cek') then
    alter table public.purchase_orders add constraint purchase_orders_mode_ppn_cek
      check (mode_ppn in ('exclude','include','non') and ppn_kena = (mode_ppn <> 'non'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'sales_orders_mode_ppn_cek') then
    alter table public.sales_orders add constraint sales_orders_mode_ppn_cek
      check (mode_ppn in ('exclude','include','non') and ppn_kena = (mode_ppn <> 'non'));
  end if;
end $$;
comment on column public.purchase_orders.mode_ppn is
  '#30 (berkas 114): exclude = harga belum termasuk PPN; include = harga sudah termasuk PPN (DPP = ÷1,11); non = tanpa PPN. ppn_kena = mode <> non.';
comment on column public.sales_orders.mode_ppn is
  '#30 (berkas 114): sama dengan purchase_orders.mode_ppn; SP yang menunjuk PO selalu mengikuti mode PO-nya.';

-- ── (2) pembantu ─────────────────────────────────────────────────────────
-- Nilai TANPA PPN dari angka yang diketik. Hanya baris barang pada mode include yang dibagi 1,11.
create or replace function public.dpp_ppn(p_nilai numeric, p_mode text, p_jenis text default 'barang')
returns numeric
language sql immutable parallel safe set search_path = '' as $$
  select case when p_mode = 'include' and coalesce(p_jenis, 'barang') = 'barang'
              then p_nilai / 1.11 else p_nilai end
$$;
create or replace function public.label_mode_ppn(p_mode text)
returns text
language sql immutable parallel safe set search_path = '' as $$
  select case p_mode when 'include' then 'Include PPN' when 'non' then 'Non-PPN'
                     when 'exclude' then 'Exclude PPN' else coalesce(p_mode, '—') end
$$;
grant execute on function public.dpp_ppn(numeric, text, text) to authenticated;
grant execute on function public.label_mode_ppn(text) to authenticated;

-- ── (3) sinkron mode_ppn ↔ ppn_kena; SP ikut mode PO ─────────────────────
create or replace function public.sinkron_mode_ppn()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_po text;
begin
  if tg_op = 'INSERT' then
    new.mode_ppn := coalesce(new.mode_ppn, case when coalesce(new.ppn_kena, true) then 'exclude' else 'non' end);
  elsif new.mode_ppn is distinct from old.mode_ppn then
    new.mode_ppn := coalesce(new.mode_ppn, old.mode_ppn);          -- mode yang ditulis menang
  elsif new.ppn_kena is distinct from old.ppn_kena then            -- klien lama: hanya ppn_kena
    new.mode_ppn := case when new.ppn_kena then 'exclude' else 'non' end;
  end if;
  -- #30: SP yang menunjuk PO selalu memakai mode PPN PO-nya (dinilai saat SP dibuat, saat PO-nya
  -- ditempel/diganti, atau saat mode/ppn_kena SP disentuh — bukan pada setiap update lain).
  -- IF bersarang: PL/pgSQL tidak memotong AND, jadi new.po_id tidak boleh disebut untuk purchase_orders
  -- (versi pertama berkas ini begitu dan menggagalkan insert PO — diperbaiki di migrasi 114b).
  if tg_table_name = 'sales_orders' then
    if new.po_id is not null
       and (tg_op = 'INSERT' or new.po_id is distinct from old.po_id
            or new.mode_ppn is distinct from old.mode_ppn or new.ppn_kena is distinct from old.ppn_kena) then
      select p.mode_ppn into v_po from public.purchase_orders p where p.id = new.po_id;
      if v_po is not null then new.mode_ppn := v_po; end if;
    end if;
  end if;
  new.ppn_kena := new.mode_ppn <> 'non';
  return new;
end $$;
revoke all on function public.sinkron_mode_ppn() from public, anon, authenticated;

drop trigger if exists po_a_mode_ppn on public.purchase_orders;
create trigger po_a_mode_ppn before insert or update on public.purchase_orders
  for each row execute function public.sinkron_mode_ppn();
drop trigger if exists so_a_mode_ppn on public.sales_orders;
create trigger so_a_mode_ppn before insert or update on public.sales_orders
  for each row execute function public.sinkron_mode_ppn();

-- Mode PPN PO berubah (lewat approval ubah PO) → SP-nya ikut. SP yang sudah ber-invoice
-- tidak boleh berubah PPN-nya diam-diam → perubahan PO-nya ditolak dengan pesan jelas.
create or replace function public.mode_ppn_po_ke_sp()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_inv text;
begin
  select string_agg(s.no_sp || ' (invoice ' || s.no_invoice || ')', ', ') into v_inv
    from public.sales_orders s
   where s.po_id = new.id and not s.batal and s.no_invoice is not null and s.mode_ppn <> new.mode_ppn;
  if v_inv is not null then
    raise exception 'Mode PPN PO % tidak bisa diubah menjadi %: Surat Pesanan % sudah ber-invoice, '
                    'dan invoice/faktur mengikuti mode PPN. Perbaiki invoicenya dulu.',
                    new.no_po, public.label_mode_ppn(new.mode_ppn), v_inv using errcode = '23514';
  end if;
  update public.sales_orders s set mode_ppn = new.mode_ppn, diubah_pada = now(), diubah_oleh = auth.uid()
   where s.po_id = new.id and not s.batal and s.mode_ppn <> new.mode_ppn;
  return null;
end $$;
revoke all on function public.mode_ppn_po_ke_sp() from public, anon, authenticated;
drop trigger if exists po_mode_ppn_sp on public.purchase_orders;
create trigger po_mode_ppn_sp after update of mode_ppn, ppn_kena on public.purchase_orders
  for each row when (old.mode_ppn is distinct from new.mode_ppn)
  execute function public.mode_ppn_po_ke_sp();

-- Cek Vonny gugur juga bila mode PPN SP berubah (dulu: ppn_kena saja).
drop trigger if exists so_vonny_gugur on public.sales_orders;
create trigger so_vonny_gugur after update on public.sales_orders
  for each row when (((old.customer_id IS DISTINCT FROM new.customer_id) OR (old.kepada IS DISTINCT FROM new.kepada)
    OR (old.alamat IS DISTINCT FROM new.alamat) OR (old.up IS DISTINCT FROM new.up) OR (old.telp IS DISTINCT FROM new.telp)
    OR (old.ppn_kena IS DISTINCT FROM new.ppn_kena) OR (old.mode_ppn IS DISTINCT FROM new.mode_ppn)
    OR (old.catatan IS DISTINCT FROM new.catatan)
    OR ((old.po_id IS NOT NULL) AND (old.po_id IS DISTINCT FROM new.po_id))
    OR ((new.po_id IS NULL) AND ((old.po_menyusul IS DISTINCT FROM new.po_menyusul)
        OR (old.po_menyusul_alasan IS DISTINCT FROM new.po_menyusul_alasan)))))
  execute function public.sp_vonny_gugur_kepala();

-- ── (4) po_ringkas: mode-aware (+ mode_ppn di ujung) ─────────────────────
create or replace view public.po_ringkas with (security_invoker = on) as
 SELECT p.id AS po_id,
    p.no_po,
    p.tanggal,
    p.nama_customer,
    p.sales_rep_id,
    p.ppn_kena,
    CASE WHEN p.mode_ppn = 'include'
         THEN COALESCE(sum(n.nilai), 0::numeric)
              - COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric)
              + COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE COALESCE(sum(n.nilai), 0::numeric) END AS sub_total,
    CASE p.mode_ppn
         WHEN 'exclude' THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) * 0.11
         WHEN 'include' THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric)
                           - COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE 0::numeric END AS ppn,
    COALESCE(sum(n.nilai), 0::numeric) +
        CASE WHEN p.mode_ppn = 'exclude'
             THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) * 0.11
             ELSE 0::numeric END AS grand_total,
    count(l.id) AS jumlah_baris,
    CASE WHEN p.mode_ppn = 'include'
         THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) END AS dasar_ppn,
    CASE WHEN p.mode_ppn = 'include'
         THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) END AS total_barang,
    COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'biaya'::text), 0::numeric) AS total_biaya,
    p.mode_ppn   -- #30 (berkas 114)
   FROM purchase_orders p
     LEFT JOIN po_lines l ON l.po_id = p.id
     LEFT JOIN LATERAL ( SELECT l.qty * l.harga -
                CASE
                    WHEN COALESCE(l.diskon_tipe, 'rp'::text) = 'persen'::text THEN l.qty * l.harga * COALESCE(l.diskon, 0::numeric) / 100::numeric
                    ELSE COALESCE(l.diskon, 0::numeric)
                END
                + COALESCE(l.penyesuaian, 0::numeric) AS nilai) n ON true   -- #34
  GROUP BY p.id;

create or replace view public.po_belum_sp with (security_invoker = on) as
 SELECT id AS po_id,
    no_po,
    tanggal,
    customer_id,
    nama_customer,
    sales_rep_id,
    ppn_kena,
    mode_ppn   -- #30 (berkas 114)
   FROM purchase_orders p
  WHERE NOT batal AND NOT (EXISTS ( SELECT 1
           FROM sales_orders s
          WHERE s.po_id = p.id AND NOT s.batal)) AND NOT (EXISTS ( SELECT 1
           FROM sales_orders s
          WHERE s.po_id = p.id AND s.batal_karena_barang));

-- ── (5) so_baris_hitung: komisi/tier/harga khusus dari DPP (+ kolom DPP di ujung) ──
create or replace view public.so_baris_hitung with (security_invoker = on) as
 SELECT l.id,
    l.so_id,
    l.urut,
    l.product_id,
    (l.qty - l.qty_batal)::numeric(14,2) AS qty,
    l.harga_nett,
    l.ehc_item,
    COALESCE(l.harga_list, harga_berlaku(l.product_id)) AS harga_list,
    (l.qty - l.qty_batal) * l.harga_nett AS nilai_barang,
    (l.qty - l.qty_batal) * l.ehc_item AS nilai_ehc,
    (l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item) AS nilai_baris,
    upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text AS hammer,
        CASE
            WHEN l.jenis = 'biaya'::text THEN NULL::numeric
            WHEN rep.komisi_flat_pct IS NOT NULL THEN rep.komisi_flat_pct
            WHEN hk.id IS NOT NULL THEN hk.komisi_pct
            WHEN s.cash_ok IS TRUE THEN komisi_tier_cash(d.nett_dpp, COALESCE(l.harga_list, harga_berlaku(l.product_id)))
            ELSE komisi_tier(d.nett_dpp, COALESCE(l.harga_list, harga_berlaku(l.product_id)), upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text)
        END AS pct,
    l.jenis,
    hk.id AS harga_khusus_id,
    l.qty AS qty_pesan,
    l.qty_batal,
    -- #30 (berkas 114): angka TANPA PPN — sama dengan kolom di atas kecuali baris barang mode include (÷ 1,11)
    COALESCE(s.mode_ppn, 'exclude'::text) AS mode_ppn,
    d.nett_dpp,
    (l.qty - l.qty_batal) * d.nett_dpp AS nilai_barang_dpp,
    (l.qty - l.qty_batal) * d.ehc_dpp AS nilai_ehc_dpp,
    (l.qty - l.qty_batal) * (d.nett_dpp + d.ehc_dpp) AS nilai_baris_dpp
   FROM sales_order_lines l
     LEFT JOIN products p ON p.id = l.product_id
     LEFT JOIN sales_orders s ON s.id = l.so_id
     LEFT JOIN sales_reps rep ON rep.id = s.sales_rep_id
     CROSS JOIN LATERAL ( SELECT dpp_ppn(l.harga_nett, s.mode_ppn, l.jenis) AS nett_dpp,
                                 dpp_ppn(l.ehc_item, s.mode_ppn, l.jenis) AS ehc_dpp) d
     LEFT JOIN LATERAL ( SELECT h.id,
            h.komisi_pct
           FROM harga_khusus h
          WHERE h.status = 'aktif'::text AND h.customer_id = s.customer_id AND h.product_id = l.product_id AND d.nett_dpp >= h.harga_nett
         LIMIT 1) hk ON l.jenis <> 'biaya'::text
  WHERE COALESCE(l.batal, false) = false AND (l.qty - l.qty_batal) > 0::numeric;

-- ── (6) so_ringkas: mode-aware; total_barang/total_ehc/komisi dari DPP (+ mode_ppn di ujung) ──
create or replace view public.so_ringkas with (security_invoker = on) as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.sales_rep_id,
    s.ppn_kena,
    s.status,
    COALESCE(sum(b.nilai_barang_dpp) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) AS total_barang,
    COALESCE(sum(b.nilai_ehc_dpp), 0::numeric) AS total_ehc,
    CASE WHEN s.mode_ppn = 'include'
         THEN COALESCE(sum(b.nilai_baris), 0::numeric)
              - COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric)
              + COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE COALESCE(sum(b.nilai_baris), 0::numeric) END AS sub_total,
    CASE s.mode_ppn
         WHEN 'exclude' THEN COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) * 0.11
         WHEN 'include' THEN COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric)
                           - COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE 0::numeric END AS ppn,
    COALESCE(sum(b.nilai_baris), 0::numeric) +
        CASE WHEN s.mode_ppn = 'exclude'
             THEN COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) * 0.11
             ELSE 0::numeric END AS grand_total,
    COALESCE(sum(b.nilai_barang_dpp * b.pct) FILTER (WHERE b.pct IS NOT NULL), 0::numeric) AS komisi,
    COALESCE(bool_or(b.pct IS NULL) FILTER (WHERE b.id IS NOT NULL AND b.jenis = 'barang'::text), false) AS ada_bawah_list,
    count(b.id) AS jumlah_baris,
    COALESCE(sum(b.nilai_barang) FILTER (WHERE b.jenis = 'biaya'::text), 0::numeric) AS total_biaya,
    CASE WHEN s.mode_ppn = 'include'
         THEN COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) / 1.11
         ELSE COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) END AS dasar_ppn,
    count(b.id) FILTER (WHERE b.jenis = 'barang'::text AND b.pct IS NULL AND COALESCE(b.harga_list, 0::numeric) > 0::numeric) AS n_bawah_list,
    count(b.id) FILTER (WHERE b.jenis = 'barang'::text AND b.pct IS NULL AND COALESCE(b.harga_list, 0::numeric) <= 0::numeric) AS n_tanpa_list,
    s.mode_ppn   -- #30 (berkas 114)
   FROM sales_orders s
     LEFT JOIN so_baris_hitung b ON b.so_id = s.id
  GROUP BY s.id;

-- ── (7) sp_nilai_batal: PPN ditambahkan hanya pada mode exclude ──────────
create or replace view public.sp_nilai_batal with (security_invoker = on) as
 SELECT so_id,
    po_id,
    no_sp,
    sp_batal,
    grand_total_awal,
    grand_total_efektif,
    qty_batal_total,
    ada_batal,
    grand_total_awal - grand_total_efektif AS nilai_batal
   FROM ( SELECT s.id AS so_id,
            s.po_id,
            s.no_sp,
            s.batal AS sp_batal,
            COALESCE(sum(l.qty * (l.harga_nett + l.ehc_item)), 0::numeric) +
                CASE
                    WHEN s.mode_ppn = 'exclude' THEN COALESCE(sum(l.qty * (l.harga_nett + l.ehc_item)) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) * 0.11
                    ELSE 0::numeric
                END AS grand_total_awal,
            COALESCE(sum((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item)) FILTER (WHERE NOT l.batal AND (l.qty - l.qty_batal) > 0::numeric), 0::numeric) +
                CASE
                    WHEN s.mode_ppn = 'exclude' THEN COALESCE(sum((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item)) FILTER (WHERE l.jenis = 'barang'::text AND NOT l.batal AND (l.qty - l.qty_batal) > 0::numeric), 0::numeric) * 0.11
                    ELSE 0::numeric
                END AS grand_total_efektif,
            COALESCE(sum(l.qty_batal), 0::numeric) AS qty_batal_total,
            COALESCE(bool_or(l.qty_batal > 0::numeric), false) AS ada_batal
           FROM sales_orders s
             JOIN sales_order_lines l ON l.so_id = s.id
          GROUP BY s.id, s.po_id, s.no_sp, s.batal, s.mode_ppn) x;

-- ── (8) cash_belum_cocok: tier cash dari DPP ─────────────────────────────
create or replace view public.cash_belum_cocok with (security_invoker = on) as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.kepada,
    s.sales_rep_id,
    s.lunas,
    s.tgl_lunas,
    s.no_invoice,
    COALESCE(r.total_barang, 0::numeric) AS total_barang,
    COALESCE(r.komisi, 0::numeric) AS komisi_sekarang,
    (( SELECT COALESCE(sum(b.nilai_barang_dpp * komisi_tier_cash(b.nett_dpp, b.harga_list)), 0::numeric) AS "coalesce"
           FROM so_baris_hitung b
          WHERE b.so_id = s.id AND b.jenis = 'barang'::text AND b.harga_khusus_id IS NULL AND komisi_tier_cash(b.nett_dpp, b.harga_list) IS NOT NULL))
    + (( SELECT COALESCE(sum(b.nilai_barang_dpp * b.pct), 0::numeric) AS "coalesce"
           FROM so_baris_hitung b
          WHERE b.so_id = s.id AND b.jenis = 'barang'::text AND b.harga_khusus_id IS NOT NULL)) AS komisi_kalau_cash
   FROM sales_orders s
     LEFT JOIN so_ringkas r ON r.so_id = s.id
  WHERE s.cash_minta AND s.cash_ok IS NULL AND NOT s.batal;

-- ── (9) periksa_total_sp: mode-aware + mode SP wajib = mode PO ───────────
create or replace function public.periksa_total_sp(p_so bigint)
returns void
language plpgsql security definer set search_path = public as $function$
declare
  v_no_sp text; v_no_po text; v_po bigint; v_baris bigint;
  v_mode text; v_mode_po text; v_sp_total numeric; v_po_total numeric;
begin
  select s.po_id, s.no_sp, s.mode_ppn into v_po, v_no_sp, v_mode
    from public.sales_orders s where s.id = p_so;
  if v_po is null then return; end if;

  select count(*) into v_baris from public.sales_order_lines where so_id = p_so;
  if v_baris = 0 then return; end if;

  -- #18: SEMUA baris (termasuk batal). #12: rumus identik sp_nilai_batal.grand_total_awal,
  -- TANPA pembulatan. #30 (berkas 114): PPN 11% ditambahkan hanya pada mode exclude;
  -- include & non-PPN = jumlah baris apa adanya.
  select
    coalesce(sum(l.qty * (l.harga_nett + l.ehc_item)), 0)
    + case when v_mode = 'exclude'
        then coalesce(sum(l.qty * (l.harga_nett + l.ehc_item)) filter (where l.jenis = 'barang'), 0) * 0.11
        else 0 end
  into v_sp_total
  from public.sales_order_lines l
  where l.so_id = p_so;

  select p.grand_total, p.no_po, p.mode_ppn into v_po_total, v_no_po, v_mode_po
    from public.po_ringkas p where p.po_id = v_po;
  if v_po_total is null then return; end if;

  -- #30: include & non-PPN bisa sama grand total-nya tapi beda pajaknya → mode dicek terpisah
  if v_mode is distinct from v_mode_po then
    raise exception 'Mode PPN Surat Pesanan % (%) harus sama dengan PO % (%) — SP mengikuti PO.',
      coalesce(v_no_sp, '(baru)'), public.label_mode_ppn(v_mode),
      coalesce(v_no_po, '(?)'), public.label_mode_ppn(v_mode_po) using errcode = '23514';
  end if;

  -- #12: sama SAMPAI SEN (presisi yang tercetak di dokumen)
  if round(coalesce(v_sp_total, 0), 2) <> round(v_po_total, 2) then
    raise exception
      'Grand total Surat Pesanan % adalah %, sedangkan PO % adalah % — selisih %. '
      'Harga nett + EHC per baris harus menjumlah persis ke angka PO. '
      'Kalau justru PO-nya yang salah, perbaiki PO-nya dulu, jangan SP-nya.',
      coalesce(v_no_sp, '(baru)'),
      public.rp_teks(coalesce(v_sp_total, 0)),
      coalesce(v_no_po, '(?)'),
      public.rp_teks(v_po_total),
      public.rp_teks(abs(coalesce(v_sp_total, 0) - v_po_total));
  end if;
end $function$;

-- ── (10) patch fungsi yang membaca harga_nett langsung / menulis ppn_kena ──
do $$
declare
  v text; w text;
  lama text[] := array[
    $a$  v_tgl date;$a$,
    $a$               l.harga_nett as u_nett,
               coalesce(l.ehc_item, 0) as u_ehc,$a$,
    $a$    v_tgl := coalesce(nullif(u.nilai_lama #>> '{kepala,tanggal}', '')::date, current_date);$a$,
    $a$from (values ('sebelum', u.nilai_lama->'baris'), ('sesudah', u.nilai_baru->'baris')) v(versi, arr)$a$,
    $a$                 coalesce(nullif(x->>'harga_nett','')::numeric, 0) as u_nett,
                 coalesce(nullif(x->>'ehc_item','')::numeric, 0) as u_ehc$a$,
    $a$                 coalesce(nullif(x->>'harga','')::numeric, 0) as u_harga,
                 coalesce(nullif(x->>'diskon','')::numeric, 0) as u_disk,$a$];
  baru text[] := array[
    $a$  v_tgl date;
  v_mode text;   -- #30 (berkas 114)$a$,
    $a$               public.dpp_ppn(l.harga_nett, s.mode_ppn, l.jenis) as u_nett,   -- #30: DPP
               public.dpp_ppn(coalesce(l.ehc_item, 0), s.mode_ppn, l.jenis) as u_ehc,$a$,
    $a$    v_tgl := coalesce(nullif(u.nilai_lama #>> '{kepala,tanggal}', '')::date, current_date);
    v_mode := case when u.jenis = 'sp' then (select s9.mode_ppn from public.sales_orders s9 where s9.id = u.ref_id)
                   else (select p9.mode_ppn from public.purchase_orders p9 where p9.id = u.ref_id) end;   -- #30$a$,
    $a$from (values ('sebelum', u.nilai_lama->'baris', coalesce(nullif(u.nilai_lama #>> '{kepala,mode_ppn}', ''), v_mode)),
                         ('sesudah', u.nilai_baru->'baris', coalesce(nullif(u.nilai_baru #>> '{kepala,mode_ppn}', ''), v_mode))) v(versi, arr, mppn)$a$,
    $a$                 public.dpp_ppn(coalesce(nullif(x->>'harga_nett','')::numeric, 0), v.mppn, 'barang') as u_nett,   -- #30
                 public.dpp_ppn(coalesce(nullif(x->>'ehc_item','')::numeric, 0), v.mppn, 'barang') as u_ehc$a$,
    $a$                 public.dpp_ppn(coalesce(nullif(x->>'harga','')::numeric, 0), v.mppn, 'barang') as u_harga,   -- #30
                 case when coalesce(x->>'diskon_tipe', 'rp') = 'persen' then coalesce(nullif(x->>'diskon','')::numeric, 0)
                      else public.dpp_ppn(coalesce(nullif(x->>'diskon','')::numeric, 0), v.mppn, 'barang') end as u_disk,$a$];
begin
  -- putuskan_ubah: mode_ppn ikut diterapkan dari usulan (PO & SP)
  v := pg_get_functiondef('public.putuskan_ubah(bigint, boolean, text)'::regprocedure);
  w := replace(v, $a$      ppn_kena      = coalesce((k->>'ppn_kena')::boolean, p.ppn_kena),$a$,
                  $a$      ppn_kena      = coalesce((k->>'ppn_kena')::boolean, p.ppn_kena),
      mode_ppn      = coalesce(nullif(k->>'mode_ppn', ''), p.mode_ppn),   -- #30 (berkas 114)$a$);
  if w = v then raise exception 'putuskan_ubah: SET ppn_kena PO tidak ditemukan.'; end if;
  v := w;
  w := replace(v, $a$      ppn_kena = coalesce((k->>'ppn_kena')::boolean, s.ppn_kena)$a$,
                  $a$      ppn_kena = coalesce((k->>'ppn_kena')::boolean, s.ppn_kena),
      mode_ppn = coalesce(nullif(k->>'mode_ppn', ''), s.mode_ppn)   -- #30 (berkas 114)$a$);
  if w = v then raise exception 'putuskan_ubah: SET ppn_kena SP tidak ditemukan.'; end if;
  execute w;

  -- laporan margin: jual & EHC dari DPP
  foreach v in array array['laporan_margin_sp(date,date)', 'laporan_margin_produk(date,date)'] loop
    w := pg_get_functiondef(v::regprocedure);
    if position('coalesce(l.harga_nett, 0)' in w) = 0 or position('coalesce(l.ehc_item, 0)' in w) = 0 then
      raise exception '%: ekspresi jual/EHC tidak ditemukan.', v;
    end if;
    w := replace(w, 'coalesce(l.harga_nett, 0)', 'public.dpp_ppn(coalesce(l.harga_nett, 0), s.mode_ppn, l.jenis)');
    w := replace(w, 'coalesce(l.ehc_item, 0)',   'public.dpp_ppn(coalesce(l.ehc_item, 0), s.mode_ppn, l.jenis)');
    execute w;
  end loop;

  -- konteks HPP untuk keputusan GM: harga & EHC dari DPP. Setiap penggantian wajib ketemu.
  w := pg_get_functiondef('public.gm_konteks_keputusan(text, bigint)'::regprocedure);
  for i in 1 .. array_length(lama, 1) loop
    if position(lama[i] in w) = 0 then
      raise exception 'gm_konteks_keputusan: bagian % tidak ditemukan.', i;
    end if;
    w := replace(w, lama[i], baru[i]);
  end loop;
  execute w;

  -- tautkan PO ke SP menyusul: mode PPN harus sama (pesan jelas sebelum cek angka)
  v := pg_get_functiondef('public.tautkan_po_sp(bigint, bigint)'::regprocedure);
  w := replace(v, $a$  -- Angkanya diperiksa DI SINI, bukan dibiarkan meledak dari trigger,$a$,
                  $a$  -- #30 (berkas 114): SP mengikuti mode PPN PO — beda mode ditolak dengan pesan yang menyebutnya.
  if v_so.mode_ppn is distinct from v_po.mode_ppn then
    raise exception 'Surat Pesanan % memakai %, sedangkan PO % memakai %. SP mengikuti PO — '
                    'ubah dulu mode PPN SP-nya (Minta ubah SP), lalu tempelkan PO-nya.',
                    v_so.no_sp, public.label_mode_ppn(v_so.mode_ppn), v_po.no_po, public.label_mode_ppn(v_po.mode_ppn)
      using errcode = '23514';
  end if;

  -- Angkanya diperiksa DI SINI, bukan dibiarkan meledak dari trigger,$a$);
  if w = v then raise exception 'tautkan_po_sp: titik sisip tidak ditemukan.'; end if;
  execute w;
end $$;
