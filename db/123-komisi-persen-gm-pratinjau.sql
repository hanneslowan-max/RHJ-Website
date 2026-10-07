-- ═══════════════════════════════════════════════════════════════════════
-- 123 · #51 komisi: persen GM dipakai untuk baris di bawah / tanpa price list + perkiraan komisi untuk sales
--
-- Keputusan Hannes (7 Okt):
--   (a) Bila GM menyetujui harga di bawah price list dan mengisi persen komisi, persen GM itu yang DIPAKAI
--       untuk baris itu (persen × nilai baris sebelum PPN). Dulu selalu Rp 0 kecuali SP telat >120 hari —
--       mis. 007/010/011/015 /MCE/IX di DEV (GM isi 17% / 17% / 2% / 1%) komisinya Rp 0.
--   (b) Perkiraan komisi DITAMPILKAN ke sales saat membuat SP, dan sales melihat komisi SP miliknya sendiri
--       di daftar & detail SP.
--
-- Rumus (tetap per baris):
--   · komisi_pct_baris = satu-satunya tempat urutan persen dasar — SAMA PERSIS dengan CASE lama di
--     so_baris_hitung.pct: biaya → tanpa komisi; sales flat (Riksa/Michael 1%, Office 0%); harga khusus
--     aktif; cash yang sudah dicocokkan finance (5%); tier 2/3/4 HAMMER/5%. NULL = di bawah list atau
--     belum ada price list (menunggu GM). Dipakai view DAN pratinjau → angka pratinjau tidak bisa berbeda.
--   · so_baris_hitung.pct TIDAK berubah (ia penanda "di bawah / tanpa list" untuk gerbang GM, status, kirim,
--     klaim). Kolom baru di ujung: pct_berlaku = pct; bila pct NULL dan GM sudah menyetujui harga
--     (harga_ok) → gm_pct (kosong = 0%); belum diputus / ditolak → NULL. sumber_pct menjelaskan asalnya.
--   · so_ringkas.komisi = Σ nilai_barang_dpp × pct_berlaku. Kolom lain (ada_bawah_list, n_bawah_list,
--     n_tanpa_list, …) tetap membaca pct → gerbang GM & status SP tidak bergeser.
--   · komisi_hitung / komisi_berlaku / komisi_belum_klaim / laporan_komisi tidak diubah — ikut lewat
--     so_ringkas.komisi. Cabang telat >120 hari tetap (total_barang × gm_pct).
--   · SP lama yang belum diklaim ikut terhitung dengan rumus baru; nominal yang SUDAH diklaim tidak
--     berubah (beku di komisi_klaim_nilai). DEV: 7 SP bergeser (+Rp 1.750.185), 0 yang sudah diklaim.
--   · gm_pct dibatasi 0–50% (sama dengan harga khusus) — persen GM kini bernilai uang; salah ketik
--     (mis. 170) ditolak.
--
-- Pratinjau (baca saja, tidak menyimpan apa pun):
--   · pratinjau_komisi_sp(rep, pelanggan, mode PPN, cash, baris, po) — owner/GM/staff/sales. Pemeriksaan
--     sama dengan saat SP disimpan: sales hanya untuk dirinya, pelanggan miliknya/belum bertuan, PO
--     miliknya; Office hanya GM/owner; sales cash-only selalu cash. Price list pada tanggal hari ini
--     (= tanggal yang dikirim form saat simpan → sama dengan snapshot isi_harga_list).
--   · komisi_sp_saya(ids) — angka RESMI untuk kolom komisi di daftar/detail SP sales (komisi_hitung, atau
--     nominal klaim bila sudah diklaim): view invoker bisa salah bagi sales (harga khusus pelanggan yang
--     sudah dipindah ke sales lain tidak terbaca; SP telat/batal).
--
-- Semua view ditulis ulang WITH (security_invoker = on) — CREATE OR REPLACE VIEW tanpa klausa itu
-- MENGHAPUSNYA (view lalu berjalan sebagai postgres & melewati RLS). Diperiksa di akhir berkas.
-- Tidak ada DROP. Tidak ada data yang diubah.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.komisi_pct_baris(p_jenis text, p_flat numeric, p_ada_hk boolean, p_hk_pct numeric,
                                                   p_cash_ok boolean, p_nett_dpp numeric, p_list numeric, p_hammer boolean)
returns numeric language sql immutable set search_path = public as $$
  select case
    when p_jenis = 'biaya'    then null
    when p_flat is not null   then p_flat
    when p_ada_hk             then p_hk_pct
    when p_cash_ok is true    then public.komisi_tier_cash(p_nett_dpp, p_list)
    else public.komisi_tier(p_nett_dpp, p_list, p_hammer)
  end
$$;
revoke all on function public.komisi_pct_baris(text, numeric, boolean, numeric, boolean, numeric, numeric, boolean) from public, anon;
grant execute on function public.komisi_pct_baris(text, numeric, boolean, numeric, boolean, numeric, numeric, boolean) to authenticated, service_role;

create or replace view public.so_baris_hitung with (security_invoker = on) as
 SELECT l.id,
    l.so_id,
    l.urut,
    l.product_id,
    ((l.qty - l.qty_batal))::numeric(14,2) AS qty,
    l.harga_nett,
    l.ehc_item,
    COALESCE(l.harga_list, harga_berlaku(l.product_id)) AS harga_list,
    ((l.qty - l.qty_batal) * l.harga_nett) AS nilai_barang,
    ((l.qty - l.qty_batal) * l.ehc_item) AS nilai_ehc,
    ((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item)) AS nilai_baris,
    (upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text) AS hammer,
    k.pct,
    l.jenis,
    hk.id AS harga_khusus_id,
    l.qty AS qty_pesan,
    l.qty_batal,
    COALESCE(s.mode_ppn, 'exclude'::text) AS mode_ppn,
    d.nett_dpp,
    ((l.qty - l.qty_batal) * d.nett_dpp) AS nilai_barang_dpp,
    ((l.qty - l.qty_batal) * d.ehc_dpp) AS nilai_ehc_dpp,
    ((l.qty - l.qty_batal) * (d.nett_dpp + d.ehc_dpp)) AS nilai_baris_dpp,
        CASE
            WHEN (l.jenis = 'biaya'::text) THEN NULL::numeric
            WHEN (k.pct IS NOT NULL) THEN k.pct
            WHEN (s.harga_ok IS TRUE) THEN COALESCE(s.gm_pct, (0)::numeric)
            ELSE NULL::numeric
        END AS pct_berlaku,
        CASE
            WHEN (l.jenis = 'biaya'::text) THEN 'biaya'::text
            WHEN (rep.komisi_flat_pct IS NOT NULL) THEN 'flat'::text
            WHEN (hk.id IS NOT NULL) THEN 'harga khusus'::text
            WHEN (k.pct IS NOT NULL) THEN (CASE WHEN (s.cash_ok IS TRUE) THEN 'cash'::text ELSE 'tier'::text END)
            WHEN (s.harga_ok IS TRUE) THEN 'gm'::text
            WHEN (s.harga_ok IS FALSE) THEN 'ditolak gm'::text
            ELSE 'menunggu gm'::text
        END AS sumber_pct
   FROM ((((((sales_order_lines l
     LEFT JOIN products p ON ((p.id = l.product_id)))
     LEFT JOIN sales_orders s ON ((s.id = l.so_id)))
     LEFT JOIN sales_reps rep ON ((rep.id = s.sales_rep_id)))
     CROSS JOIN LATERAL ( SELECT dpp_ppn(l.harga_nett, s.mode_ppn, l.jenis) AS nett_dpp,
            dpp_ppn(l.ehc_item, s.mode_ppn, l.jenis) AS ehc_dpp) d)
     LEFT JOIN LATERAL ( SELECT h.id,
            h.komisi_pct
           FROM harga_khusus h
          WHERE ((h.status = 'aktif'::text) AND (h.customer_id = s.customer_id) AND (h.product_id = l.product_id) AND (d.nett_dpp >= h.harga_nett))
         LIMIT 1) hk ON ((l.jenis <> 'biaya'::text)))
     CROSS JOIN LATERAL ( SELECT komisi_pct_baris(l.jenis, rep.komisi_flat_pct, (hk.id IS NOT NULL), hk.komisi_pct, s.cash_ok, d.nett_dpp,
            COALESCE(l.harga_list, harga_berlaku(l.product_id)), (upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text)) AS pct) k)
  WHERE ((COALESCE(l.batal, false) = false) AND ((l.qty - l.qty_batal) > (0)::numeric));

create or replace view public.so_ringkas with (security_invoker = on) as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.sales_rep_id,
    s.ppn_kena,
    s.status,
    COALESCE(sum(b.nilai_barang_dpp) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) AS total_barang,
    COALESCE(sum(b.nilai_ehc_dpp), (0)::numeric) AS total_ehc,
        CASE
            WHEN (s.mode_ppn = 'include'::text) THEN ((COALESCE(sum(b.nilai_baris), (0)::numeric) - COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric)) + (COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) / 1.11))
            ELSE COALESCE(sum(b.nilai_baris), (0)::numeric)
        END AS sub_total,
        CASE s.mode_ppn
            WHEN 'exclude'::text THEN (COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) * 0.11)
            WHEN 'include'::text THEN (COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) - (COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) / 1.11))
            ELSE (0)::numeric
        END AS ppn,
    (COALESCE(sum(b.nilai_baris), (0)::numeric) +
        CASE
            WHEN (s.mode_ppn = 'exclude'::text) THEN (COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) * 0.11)
            ELSE (0)::numeric
        END) AS grand_total,
    COALESCE(sum((b.nilai_barang_dpp * b.pct_berlaku)) FILTER (WHERE (b.pct_berlaku IS NOT NULL)), (0)::numeric) AS komisi,
    COALESCE(bool_or((b.pct IS NULL)) FILTER (WHERE ((b.id IS NOT NULL) AND (b.jenis = 'barang'::text))), false) AS ada_bawah_list,
    count(b.id) AS jumlah_baris,
    COALESCE(sum(b.nilai_barang) FILTER (WHERE (b.jenis = 'biaya'::text)), (0)::numeric) AS total_biaya,
        CASE
            WHEN (s.mode_ppn = 'include'::text) THEN (COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric) / 1.11)
            ELSE COALESCE(sum(b.nilai_baris) FILTER (WHERE (b.jenis = 'barang'::text)), (0)::numeric)
        END AS dasar_ppn,
    count(b.id) FILTER (WHERE ((b.jenis = 'barang'::text) AND (b.pct IS NULL) AND (COALESCE(b.harga_list, (0)::numeric) > (0)::numeric))) AS n_bawah_list,
    count(b.id) FILTER (WHERE ((b.jenis = 'barang'::text) AND (b.pct IS NULL) AND (COALESCE(b.harga_list, (0)::numeric) <= (0)::numeric))) AS n_tanpa_list,
    s.mode_ppn
   FROM (sales_orders s
     LEFT JOIN so_baris_hitung b ON ((b.so_id = s.id)))
  GROUP BY s.id;

-- gm_pct kini bernilai uang untuk baris di bawah / tanpa list → dibatasi seperti harga khusus (hk_pct_wajar)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'so_gm_pct_wajar' and conrelid = 'public.sales_orders'::regclass) then
    alter table public.sales_orders add constraint so_gm_pct_wajar check (gm_pct is null or (gm_pct >= 0 and gm_pct <= 0.5));
  end if;
end $$;

-- ── pratinjau komisi saat SP dibuat (baca saja) ─────────────────────────
create or replace function public.pratinjau_komisi_sp(p_sales_rep bigint, p_customer bigint, p_mode_ppn text,
                                                      p_cash_minta boolean, p_baris jsonb, p_po bigint default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_peran   text := public.peran_saya();
  v_rep     bigint := p_sales_rep;
  v_cust    bigint := p_customer;
  v_mode    text := coalesce(nullif(btrim(coalesce(p_mode_ppn, '')), ''), 'exclude');
  v_cash    boolean := coalesce(p_cash_minta, false);
  v_flat    numeric;
  v_cash_only boolean;
  v_po      record;
  e         jsonb;
  v_n       int := 0;
  v_i       int;
  v_jenis   text;
  v_prod    bigint;
  v_qty     numeric;
  v_nett    numeric;
  v_dpp     numeric;
  v_list    numeric;
  v_hammer  boolean;
  v_hk_id   bigint;
  v_hk_pct  numeric;
  v_pct     numeric;
  v_pct_c   numeric;
  v_status  text;
  v_nilai   numeric;
  v_tunggu  boolean;
  v_baris   jsonb := '[]'::jsonb;
  v_total   numeric := 0;
  v_total_c numeric := 0;
  v_ada_c   boolean := false;
  v_n_bawah int := 0;
  v_n_tanpa int := 0;
  v_dasar   numeric := 0;
begin
  if auth.uid() is null or not public.boleh_alur_jual() then
    raise exception 'Perkiraan komisi hanya untuk pembuat Surat Pesanan (sales, staff, GM, owner).' using errcode = '42501';
  end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' then
    raise exception 'Baris pratinjau harus berupa daftar.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_baris) > 300 then
    raise exception 'Terlalu banyak baris untuk dipratinjau (maks 300).' using errcode = '22023';
  end if;

  -- SP dari PO: pelanggan & mode PPN ikut PO (sinkron_mode_ppn), sales dari PO bila tidak dipilih
  if p_po is not null then
    select p.id, p.mode_ppn, p.customer_id, p.sales_rep_id into v_po from public.purchase_orders p where p.id = p_po;
    if v_po.id is null then raise exception 'PO #% tidak ditemukan.', p_po using errcode = 'P0002'; end if;
    if v_peran = 'sales' and v_po.sales_rep_id is distinct from public.sales_rep_saya() then
      raise exception 'PO ini bukan milik Anda.' using errcode = '42501';
    end if;
    v_mode := coalesce(v_po.mode_ppn, v_mode);
    v_cust := v_po.customer_id;
    v_rep  := coalesce(v_rep, v_po.sales_rep_id);
  end if;
  if v_mode not in ('exclude', 'include', 'non') then
    raise exception 'Mode PPN hanya exclude, include, atau non.' using errcode = '22023';
  end if;

  -- cermin jaga_pemilik_dokumen / RLS so_tambah / jaga_sp_hanya_gm / jaga_cash_only
  if v_peran = 'sales' then
    if public.sales_rep_saya() is null then
      raise exception 'Akun sales Anda belum ditautkan ke data sales.' using errcode = '42501';
    end if;
    if v_rep is not null and v_rep <> public.sales_rep_saya() then
      raise exception 'Sales SP harus diri Anda sendiri.' using errcode = '42501';
    end if;
    v_rep := public.sales_rep_saya();
  end if;
  if not public.pelanggan_saya(v_cust) then
    raise exception 'Pelanggan ini dipegang sales lain.' using errcode = '42501';
  end if;
  if not public.setara_owner() and public.sp_khusus_gm(v_rep, v_cust) then
    raise exception 'SP untuk pelanggan Office hanya dibuat GM atau owner (pelanggan kantor, tanpa komisi). Minta GM yang membuatkan SP-nya.'
      using errcode = '42501';
  end if;
  select r.komisi_flat_pct, coalesce(r.cash_only, false) into v_flat, v_cash_only from public.sales_reps r where r.id = v_rep;
  if v_cash_only then v_cash := true; end if;

  for e in select x from jsonb_array_elements(p_baris) as t(x) loop
    v_n := v_n + 1;
    v_i := coalesce(nullif(e->>'i', '')::int, v_n - 1);
    v_jenis := coalesce(nullif(e->>'jenis', ''), 'barang');
    v_prod := case when v_jenis = 'biaya' then null else nullif(e->>'product_id', '')::bigint end;
    v_qty := coalesce(nullif(e->>'qty', '')::numeric, 0);
    v_nett := coalesce(nullif(e->>'harga_nett', '')::numeric, 0);
    v_dpp := public.dpp_ppn(v_nett, v_mode, v_jenis);
    v_list := case when v_prod is null then null else public.harga_berlaku_hitung(v_prod, current_date) end;
    v_hammer := coalesce((select upper(coalesce(pr.brand, '')) = 'HAMMER' from public.products pr where pr.id = v_prod), false);
    v_hk_id := null; v_hk_pct := null;
    if v_jenis <> 'biaya' and v_cust is not null and v_prod is not null then
      select h.id, h.komisi_pct into v_hk_id, v_hk_pct from public.harga_khusus h
       where h.status = 'aktif' and h.customer_id = v_cust and h.product_id = v_prod and v_dpp >= h.harga_nett limit 1;
    end if;
    v_pct := public.komisi_pct_baris(v_jenis, v_flat, v_hk_id is not null, v_hk_pct, null, v_dpp, v_list, v_hammer);
    v_pct_c := case when v_cash and v_flat is null and v_hk_id is null and v_jenis <> 'biaya'
                    then public.komisi_tier_cash(v_dpp, v_list) end;
    v_nilai := v_qty * v_dpp;
    v_tunggu := false;
    v_status := case
      when v_qty <= 0              then 'kosong'
      when v_jenis = 'biaya'       then 'biaya'
      when v_flat is not null      then 'flat'
      when v_hk_id is not null     then 'khusus'
      when v_pct is not null       then 'tier'
      when coalesce(v_list, 0) > 0 then 'bawah_list'
      else 'tanpa_list' end;
    if v_status in ('bawah_list', 'tanpa_list') then
      if v_status = 'bawah_list' then v_n_bawah := v_n_bawah + 1; else v_n_tanpa := v_n_tanpa + 1; end if;
      v_dasar := v_dasar + v_nilai;
      v_tunggu := v_cust is not null and v_prod is not null and exists (
        select 1 from public.harga_khusus h where h.status = 'menunggu' and h.customer_id = v_cust and h.product_id = v_prod);
    end if;
    if v_qty > 0 then
      v_total := v_total + coalesce(v_nilai * v_pct, 0);
      if v_pct_c is not null then v_ada_c := true; end if;
      v_total_c := v_total_c + coalesce(v_nilai * coalesce(v_pct_c, v_pct), 0);
    end if;
    v_baris := v_baris || jsonb_build_object(
      'i', v_i, 'product_id', v_prod, 'jenis', v_jenis, 'nett_dpp', v_dpp, 'harga_list', v_list,
      'nilai_dpp', v_nilai, 'pct', v_pct, 'komisi', case when v_qty > 0 then v_nilai * v_pct end,
      'status', v_status, 'pct_bila_cash', v_pct_c,
      'komisi_bila_cash', case when v_qty > 0 and v_pct_c is not null then v_nilai * v_pct_c end,
      'harga_khusus_id', v_hk_id, 'harga_khusus_menunggu', v_tunggu);
  end loop;

  return jsonb_build_object(
    'baris', v_baris, 'komisi', v_total,
    'komisi_bila_cash', case when v_ada_c then v_total_c end,
    'n_bawah_list', v_n_bawah, 'n_tanpa_list', v_n_tanpa, 'dasar_menunggu', v_dasar,
    'flat_pct', v_flat, 'sales_rep_id', v_rep, 'customer_id', v_cust, 'mode_ppn', v_mode,
    'cash_minta', v_cash, 'tanggal', current_date);
end $$;
revoke all on function public.pratinjau_komisi_sp(bigint, bigint, text, boolean, jsonb, bigint) from public, anon;
grant execute on function public.pratinjau_komisi_sp(bigint, bigint, text, boolean, jsonb, bigint) to authenticated;

-- ── angka resmi komisi untuk kolom daftar/detail SP sales ───────────────
create or replace function public.komisi_sp_saya(p_ids bigint[])
returns table (so_id bigint, komisi numeric, diklaim boolean, menunggu_gm boolean, n_bawah_list int, n_tanpa_list int,
               telat boolean, batal boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Belum masuk.' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 1000 then
    raise exception 'Terlalu banyak SP sekaligus (maks 1000).' using errcode = '22023';
  end if;
  return query
    select s.id,
           case when s.batal then null else coalesce(kk.nominal, public.komisi_hitung(s.id)) end,
           kk.id is not null,
           coalesce(r.ada_bawah_list, false) and s.harga_ok is not true and not s.batal,
           coalesce(r.n_bawah_list, 0)::int, coalesce(r.n_tanpa_list, 0)::int,
           coalesce(s.telat, false), s.batal
      from (select distinct unnest(p_ids) as id) x
      join public.sales_orders s on s.id = x.id
      left join public.so_ringkas r on r.so_id = s.id
      left join lateral (select k.id, n.nominal from public.komisi_klaim k
                           left join public.komisi_klaim_nilai n on n.klaim_id = k.id
                          where k.so_id = s.id order by k.id desc limit 1) kk on true
     where public.boleh_lihat_hpp()
        or (public.peran_saya() = 'sales' and s.sales_rep_id = public.sales_rep_saya());
end $$;
revoke all on function public.komisi_sp_saya(bigint[]) from public, anon;
grant execute on function public.komisi_sp_saya(bigint[]) to authenticated;

-- ── pemeriksaan: kedua view tetap security_invoker (RLS) ────────────────
do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relname in ('so_baris_hitung', 'so_ringkas')
                and not coalesce(c.reloptions, '{}') @> array['security_invoker=on']) then
    raise exception 'so_baris_hitung / so_ringkas kehilangan security_invoker — migrasi dibatalkan.';
  end if;
end $$;
