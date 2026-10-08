-- ═══════════════════════════════════════════════════════════════════════
-- 130 · #51 lanjutan (keputusan Hannes 7 Okt): harga khusus hanya di bawah list, sales flat ke gerbang GM,
--       penggolongan baris SP DIBEKUKAN saat SP dibuat
--
-- (1) Harga khusus hanya berlaku bila harga jual (DPP) DI BAWAH price list baris itu. Di atas / sama dengan list →
--     kembali ke tier (dulu harga khusus mengalahkan tier walau harga jual di atas list, mis. 0,5% padahal tier 5%).
--     Baris tanpa price list tetap boleh ditutup harga khusus (tidak ada tier untuknya).
-- (2) Riksa & Michael (sales komisi flat, bukan Office/sp_hanya_gm): baris yang harganya di bawah price list
--     MASUK gerbang GM (antrean 'harga', status 'menunggu gm', surat jalan & klaim tertahan sampai diputus) —
--     komisinya TETAP flat 1% (pct/pct_berlaku/so_ringkas.komisi tidak berubah). Baris yang ditutup harga khusus
--     tidak ditahan. Baris tanpa price list tidak ditahan (keputusan hanya "di bawah list"; komisinya sudah pasti).
--     Kolom baru so_baris_hitung.perlu_gm = baris yang menahan SP di gerbang GM; untuk sales non-flat sama
--     persis dengan "pct IS NULL" (dulu). so_ringkas.ada_bawah_list / n_bawah_list / n_tanpa_list dihitung dari
--     perlu_gm → semua gerbang yang membaca so_ringkas (status_sp_hitung, jaga_urutan_dokumen_sp,
--     gerbang_kirim_sp, jaga_gerbang_komisi, komisi_sp_saya, cek_kelayakan_vonny) ikut tanpa diubah.
-- (3) Penggolongan dibekukan: price list / harga khusus yang disahkan SESUDAH SP dibuat tidak mengubah komisi
--     maupun gerbang SP itu (dulu so_baris_hitung jatuh ke harga_berlaku() HARI INI bila harga_list kosong —
--     mis. usulan yang disahkan sesudah SP dibuat mengeluarkan barisnya dari gerbang GM tanpa keputusan; dan
--     harga khusus dibaca dari keadaannya hari ini).
--     · harga_list: tanpa cadangan harga_berlaku(); trigger baru sol_zz_list_beku (sesudah a_sol_harga_list):
--       UPDATE tanpa ganti produk → harga_list lama dipertahankan (juga bila kosong; dulu yang kosong dihitung
--       ulang di setiap UPDATE); INSERT / ganti produk → price list per saat SP DIBUAT (berlaku pada tanggal SP
--       DAN sudah ada saat SP dibuat); INSERT dari "Minta ubah SP" (putuskan_ubah menghapus & menyisipkan ulang
--       semua baris) → produk yang sudah ada di SP membawa harga_list lamanya dari nilai_lama usulan.
--       isi_harga_list & putuskan_ubah TIDAK diubah.
--     · harga khusus: dibaca per saat SP dibuat dari harga_khusus_log (status/harga/persen pada
--       sales_orders.dibuat_pada) — yang disetujui / diubah / dinonaktifkan sesudahnya tidak berpengaruh.
--       Pengecualian: harga khusus yang DIAJUKAN DARI SP ITU (harga_khusus.so_id) berlaku per saat pertama kali
--       disetujui — itu memang keputusan GM untuk SP tersebut.
--     · Data lama: baris yang harga_list-nya kosong padahal price list sudah ada saat SP dibuat (baris dari
--       sebelum trigger isi_harga_list) diisi sekali (DEV: 0 baris), dicatat di audit_log.
-- (4) pratinjau_komisi_sp (form SP) ikut aturan (1) dan (2): per baris 'perlu_gm', ringkasan 'n_flat_gm'.
-- (5) Status SP yang tersimpan dihitung ulang (status_sp_hitung) — SP yang barisnya tadinya lolos gerbang karena
--     price list disahkan belakangan kembali 'menunggu gm' (DEV: 018/IX, 011/X; 008/X sudah lunas → tetap lunas,
--     klaim komisinya menunggu keputusan GM).
--
-- Objek bersama sesi EHC/komisi: so_ringkas & antrean_gm diubah HANYA lewat penggantian teks "b.pct IS NULL" →
-- "b.perlu_gm" pada definisi hidup (gagal bila jumlah kemunculannya tidak sesuai), cabang lain tidak disentuh.
-- Tidak ada DROP. Ketiga view tetap security_invoker (diperiksa di akhir).
-- ═══════════════════════════════════════════════════════════════════════

-- ── (3) harga_list beku ─────────────────────────────────────────────────
create or replace function public.beku_harga_list_baris()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_tgl date; v_dibuat timestamptz; v_lama jsonb; x jsonb;
begin
  if tg_op = 'UPDATE' and new.product_id is not distinct from old.product_id then
    new.harga_list := old.harga_list;   -- beku sejak baris dibuat, juga bila kosong
    return new;
  end if;
  select so.tanggal, so.dibuat_pada into v_tgl, v_dibuat from public.sales_orders so where so.id = new.so_id;
  if not found then return new; end if;   -- FK yang menolak
  -- price list per saat SP DIBUAT: berlaku pada tanggal SP dan sudah tercatat ketika SP dibuat
  new.harga_list := (select pl.harga from public.price_list pl
                      where pl.product_id = new.product_id
                        and pl.berlaku_dari <= v_tgl
                        and pl.dibuat_pada <= v_dibuat
                      order by pl.berlaku_dari desc, pl.id desc
                      limit 1);
  -- Minta ubah SP: putuskan_ubah menyisipkan ulang semua baris → produk yang sudah ada membawa harga_list lamanya
  if tg_op = 'INSERT' and new.product_id is not null
     and coalesce(current_setting('rhj.usul', true), '') = 'on' then
    select u.nilai_lama -> 'baris' into v_lama
      from public.usul_ubah u
     where u.jenis = 'sp' and u.ref_id = new.so_id and u.status = 'menunggu';
    if jsonb_typeof(v_lama) = 'array' then
      select e.v into x
        from jsonb_array_elements(v_lama) with ordinality e(v, o)
       where nullif(e.v->>'product_id', '') = new.product_id::text
         and e.v ? 'harga_list'
       order by (e.v->>'urut' = new.urut::text) desc, e.o
       limit 1;
      if x is not null then
        new.harga_list := case when coalesce(x->>'harga_list', '') ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$'
                               then (x->>'harga_list')::numeric end;
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.beku_harga_list_baris() from public, anon, authenticated;

create or replace trigger sol_zz_list_beku
  before insert or update on public.sales_order_lines
  for each row execute function public.beku_harga_list_baris();

-- data lama: harga_list kosong padahal price list sudah ada saat SP dibuat (baris dari sebelum isi_harga_list)
do $$
declare r record; n int := 0;
begin
  set local session_replication_role = replica;   -- tanpa trigger: status/total/audit otomatis tidak tersentuh
  for r in
    select l.id, to_jsonb(l) as lama, x.harga
      from public.sales_order_lines l
      join public.sales_orders s on s.id = l.so_id
      cross join lateral (select pl.harga from public.price_list pl
                           where pl.product_id = l.product_id and pl.berlaku_dari <= s.tanggal
                             and pl.dibuat_pada <= s.dibuat_pada
                           order by pl.berlaku_dari desc, pl.id desc limit 1) x
     where l.harga_list is null and l.product_id is not null and x.harga is not null
     order by l.id
       for update of l
  loop
    update public.sales_order_lines set harga_list = r.harga where id = r.id;
    insert into public.audit_log (tabel, baris_id, aksi, oleh, oleh_email, pada, sebelum, sesudah)
    select 'sales_order_lines', r.id, 'UPDATE', null, 'migrasi 130 (harga_list per saat SP dibuat)', now(),
           r.lama, to_jsonb(l2)
      from public.sales_order_lines l2 where l2.id = r.id;
    n := n + 1;
  end loop;
  set local session_replication_role = origin;
  raise notice '130: harga_list lama diisi pada % baris', n;
end $$;

-- ── (1)+(2)+(3) so_baris_hitung ─────────────────────────────────────────
create or replace view public.so_baris_hitung with (security_invoker = on) as
 SELECT l.id,
    l.so_id,
    l.urut,
    l.product_id,
    (l.qty - l.qty_batal)::numeric(14,2) AS qty,
    l.harga_nett,
    l.ehc_item,
    l.harga_list::numeric AS harga_list,                       -- 130: beku (tanpa cadangan harga_berlaku hari ini)
    (l.qty - l.qty_batal) * l.harga_nett AS nilai_barang,
    (l.qty - l.qty_batal) * l.ehc_item AS nilai_ehc,
    (l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item) AS nilai_baris,
    upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text AS hammer,
    k.pct,
    l.jenis,
    hk.id AS harga_khusus_id,
    l.qty AS qty_pesan,
    l.qty_batal,
    COALESCE(s.mode_ppn, 'exclude'::text) AS mode_ppn,
    d.nett_dpp,
    (l.qty - l.qty_batal) * d.nett_dpp AS nilai_barang_dpp,
    (l.qty - l.qty_batal) * d.ehc_dpp AS nilai_ehc_dpp,
    (l.qty - l.qty_batal) * (d.nett_dpp + d.ehc_dpp) AS nilai_baris_dpp,
        CASE
            WHEN l.jenis = 'biaya'::text THEN NULL::numeric
            WHEN k.pct IS NOT NULL THEN k.pct
            WHEN s.harga_ok IS TRUE THEN COALESCE(s.gm_pct_harga, 0::numeric)
            ELSE NULL::numeric
        END AS pct_berlaku,
        CASE
            WHEN l.jenis = 'biaya'::text THEN 'biaya'::text
            WHEN rep.komisi_flat_pct IS NOT NULL THEN 'flat'::text
            WHEN hk.id IS NOT NULL THEN 'harga khusus'::text
            WHEN k.pct IS NOT NULL THEN
            CASE
                WHEN s.cash_ok IS TRUE THEN 'cash'::text
                ELSE 'tier'::text
            END
            WHEN s.harga_ok IS TRUE THEN 'gm'::text
            WHEN s.harga_ok IS FALSE THEN 'ditolak gm'::text
            ELSE 'menunggu gm'::text
        END AS sumber_pct,
    -- 130: baris yang menahan SP di gerbang GM (non-flat: = pct IS NULL; flat bukan Office: di bawah list beku
    -- dan tidak ditutup harga khusus — komisinya tetap flat)
    COALESCE(l.jenis = 'barang'::text
             AND (k.pct IS NULL
                  OR (rep.komisi_flat_pct IS NOT NULL AND NOT COALESCE(rep.sp_hanya_gm, false)
                      AND hk.id IS NULL AND COALESCE(l.harga_list, 0::numeric) > 0::numeric
                      AND d.nett_dpp < l.harga_list)), false) AS perlu_gm
   FROM sales_order_lines l
     LEFT JOIN products p ON p.id = l.product_id
     LEFT JOIN sales_orders s ON s.id = l.so_id
     LEFT JOIN sales_reps rep ON rep.id = s.sales_rep_id
     CROSS JOIN LATERAL ( SELECT dpp_ppn(l.harga_nett, s.mode_ppn, l.jenis) AS nett_dpp,
            dpp_ppn(l.ehc_item, s.mode_ppn, l.jenis) AS ehc_dpp) d
     -- 130: harga khusus per saat SP dibuat (yang diajukan dari SP ini: per saat pertama disetujui), dan hanya
     -- bila harga jual di bawah price list beku (baris tanpa list: boleh)
     LEFT JOIN LATERAL ( SELECT h.id,
            x.komisi_pct
           FROM harga_khusus h
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN h.so_id = s.id THEN GREATEST(s.dibuat_pada, COALESCE(( SELECT min(g.diubah_pada) AS min
                               FROM harga_khusus_log g
                              WHERE g.harga_khusus_id = h.id AND g.status = 'aktif'::text), h.diputus_pada, s.dibuat_pada))
                            ELSE s.dibuat_pada
                        END AS t) w
             LEFT JOIN LATERAL ( SELECT true AS ada,
                    g.status,
                    g.harga_nett,
                    g.komisi_pct
                   FROM harga_khusus_log g
                  WHERE g.harga_khusus_id = h.id AND g.diubah_pada <= w.t
                  ORDER BY g.diubah_pada DESC, g.id DESC
                 LIMIT 1) gs ON true
             LEFT JOIN LATERAL ( SELECT true AS ada,
                    g.lama_status,
                    g.lama_harga,
                    g.lama_pct
                   FROM harga_khusus_log g
                  WHERE g.harga_khusus_id = h.id AND g.diubah_pada > w.t
                  ORDER BY g.diubah_pada, g.id
                 LIMIT 1) ga ON true
             CROSS JOIN LATERAL ( SELECT
                        CASE
                            WHEN gs.ada THEN gs.status
                            WHEN ga.ada THEN ga.lama_status
                            WHEN COALESCE(h.diputus_pada, h.diajukan_pada) <= w.t THEN h.status
                            ELSE NULL::text
                        END AS status,
                        CASE
                            WHEN gs.ada THEN gs.harga_nett
                            WHEN ga.ada THEN ga.lama_harga
                            ELSE h.harga_nett
                        END AS harga_nett,
                        CASE
                            WHEN gs.ada THEN gs.komisi_pct
                            WHEN ga.ada THEN ga.lama_pct
                            ELSE h.komisi_pct
                        END AS komisi_pct) x
          WHERE h.customer_id = s.customer_id AND h.product_id = l.product_id
            AND x.status = 'aktif'::text AND d.nett_dpp >= x.harga_nett
            AND (COALESCE(l.harga_list, 0::numeric) <= 0::numeric OR d.nett_dpp < l.harga_list)
          ORDER BY (h.so_id IS NOT DISTINCT FROM s.id) DESC, h.id DESC
         LIMIT 1) hk ON l.jenis <> 'biaya'::text
     CROSS JOIN LATERAL ( SELECT komisi_pct_baris(l.jenis, rep.komisi_flat_pct, hk.id IS NOT NULL, hk.komisi_pct, s.cash_ok, d.nett_dpp, l.harga_list, upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text) AS pct
         OFFSET 0) k
  WHERE COALESCE(l.batal, false) = false AND (l.qty - l.qty_batal) > 0::numeric;

-- ── (2) so_ringkas & antrean_gm: hanya predikat "b.pct IS NULL" → "b.perlu_gm" ─────────────────────────────
do $$
declare v_def text; v_n int;
begin
  v_def := pg_get_viewdef('public.so_ringkas'::regclass);
  v_n := (length(v_def) - length(replace(v_def, 'b.pct IS NULL', ''))) / length('b.pct IS NULL');
  if v_n <> 3 then
    raise exception '130: so_ringkas memuat "b.pct IS NULL" % kali (diharapkan 3: ada_bawah_list, n_bawah_list, n_tanpa_list) — periksa definisinya dulu.', v_n;
  end if;
  execute 'create or replace view public.so_ringkas with (security_invoker = on) as '
          || replace(v_def, 'b.pct IS NULL', 'b.perlu_gm');

  v_def := pg_get_viewdef('public.antrean_gm'::regclass);
  v_n := (length(v_def) - length(replace(v_def, 'b.pct IS NULL', ''))) / length('b.pct IS NULL');
  if v_n <> 1 then
    raise exception '130: antrean_gm memuat "b.pct IS NULL" % kali (diharapkan 1: cabang harga) — periksa definisinya dulu.', v_n;
  end if;
  execute 'create or replace view public.antrean_gm with (security_invoker = on) as '
          || replace(v_def, 'b.pct IS NULL', 'b.perlu_gm');
end $$;

-- ── (4) pratinjau_komisi_sp: aturan (1) + (2) untuk form SP ──────────────────────────────────────────────
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
  v_hanya_gm boolean;
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
  v_perlu   boolean;
  v_baris   jsonb := '[]'::jsonb;
  v_total   numeric := 0;
  v_total_c numeric := 0;
  v_ada_c   boolean := false;
  v_n_bawah int := 0;
  v_n_tanpa int := 0;
  v_n_flat  int := 0;
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
  select r.komisi_flat_pct, coalesce(r.cash_only, false), coalesce(r.sp_hanya_gm, false)
    into v_flat, v_cash_only, v_hanya_gm from public.sales_reps r where r.id = v_rep;
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
    if v_jenis <> 'biaya' and v_cust is not null and v_prod is not null
       and (coalesce(v_list, 0) <= 0 or v_dpp < v_list) then   -- 130: harga khusus hanya di bawah list
      select h.id, h.komisi_pct into v_hk_id, v_hk_pct from public.harga_khusus h
       where h.status = 'aktif' and h.customer_id = v_cust and h.product_id = v_prod and v_dpp >= h.harga_nett
       order by h.id desc limit 1;
    end if;
    v_pct := public.komisi_pct_baris(v_jenis, v_flat, v_hk_id is not null, v_hk_pct, null, v_dpp, v_list, v_hammer);
    v_pct_c := case when v_cash and v_flat is null and v_hk_id is null and v_jenis <> 'biaya'
                    then public.komisi_tier_cash(v_dpp, v_list) end;
    v_nilai := v_qty * v_dpp;
    v_tunggu := false;
    -- 130: sama dengan so_baris_hitung.perlu_gm
    v_perlu := v_qty > 0 and v_jenis = 'barang'
               and (v_pct is null
                    or (v_flat is not null and not v_hanya_gm and v_hk_id is null
                        and coalesce(v_list, 0) > 0 and v_dpp < v_list));
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
    end if;
    if v_status = 'flat' and v_perlu then v_n_flat := v_n_flat + 1; end if;
    if v_perlu and v_cust is not null and v_prod is not null then
      v_tunggu := exists (select 1 from public.harga_khusus h
                           where h.status = 'menunggu' and h.customer_id = v_cust and h.product_id = v_prod);
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
      'harga_khusus_id', v_hk_id, 'harga_khusus_menunggu', v_tunggu, 'perlu_gm', v_perlu);
  end loop;

  return jsonb_build_object(
    'baris', v_baris, 'komisi', v_total,
    'komisi_bila_cash', case when v_ada_c then v_total_c end,
    'n_bawah_list', v_n_bawah, 'n_tanpa_list', v_n_tanpa, 'n_flat_gm', v_n_flat, 'dasar_menunggu', v_dasar,
    'flat_pct', v_flat, 'sales_rep_id', v_rep, 'customer_id', v_cust, 'mode_ppn', v_mode,
    'cash_minta', v_cash, 'tanggal', current_date);
end $$;
revoke all on function public.pratinjau_komisi_sp(bigint, bigint, text, boolean, jsonb, bigint) from public, anon;
grant execute on function public.pratinjau_komisi_sp(bigint, bigint, text, boolean, jsonb, bigint) to authenticated;

-- ── (5) status tersimpan dihitung ulang (jalur yang sama dengan trigger so_sesudah_ubah) ──────────────────
do $$
declare n int;
begin
  perform set_config('rhj.hitung_status', 'on', true);
  update public.sales_orders s set status = public.status_sp_hitung(s.id)
   where s.status is distinct from public.status_sp_hitung(s.id);
  get diagnostics n = row_count;
  perform set_config('rhj.hitung_status', 'off', true);
  raise notice '130: status % SP dihitung ulang', n;
end $$;

-- ── pemeriksaan akhir ─────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_class c
              where c.oid in ('public.so_baris_hitung'::regclass, 'public.so_ringkas'::regclass, 'public.antrean_gm'::regclass)
                and not coalesce(c.reloptions::text[] @> array['security_invoker=on'], false)) then
    raise exception '130: view komisi harus tetap security_invoker';
  end if;
end $$;
