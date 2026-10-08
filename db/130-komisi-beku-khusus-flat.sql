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
-- (6) Hasil review adversarial (DEV: migrasi 130b):
--     · Patokan beku = sales_orders.dibuat_pada — kini DIISI SISTEM saat INSERT (trigger so_a_dibuat_kini; dulu
--       sales bisa mengirim dibuat_pada lampau lewat REST → price list lama / harga khusus yang sudah dinonaktifkan
--       dipakai lagi, gerbang GM terlewati). Impor/migrasi tanpa sesi (auth.uid() kosong) apa adanya.
--     · Price list per saat SP dibuat direkonstruksi dari audit_log (harga_list_pada): baris price_list yang
--       DIUBAH di tempat (upsert tanggal berlaku sama, edit massal) atau dihapus sesudah SP dibuat dibaca dengan
--       nilai sebelum perubahan (dulu nilai hasil edit ikut dipakai baris yang disisipkan belakangan).
--     · Gerbang flat tidak berlaku surut ke SP yang barangnya sudah keluar (surat jalan / kirim bertahap) — SP lama
--       Riksa/Michael yang sudah dikirim, ditagih, atau lunas tidak tertahan ulang (dan Tolak tidak bisa
--       mengunci klaim komisi flat-nya).
--     · Persetujuan harga GM tanpa persen pada SP sales flat GUGUR bila sales SP diganti ke sales non-flat (trigger
--       so_zz_flat_gm_gugur) — SP kembali ke antrean supaya GM menetapkan persen (dulu diam-diam 0%).
--     · Permintaan harga khusus yang masih menunggu hanya menahan SP PENGAJUnya dari antrean 'harga' (antrean_gm:
--       + h.so_id = s.id); SP lain untuk pasangan yang sama langsung tampil untuk diputus GM (harga khusus yang
--       disetujui sesudah SP itu dibuat tidak berlaku untuknya). ajukan_harga_khusus: pengajuan ulang untuk
--       pasangan yang masih menunggu TIDAK lagi memindahkan so_id dari SP pengaju pertama.
--
-- Objek bersama sesi EHC/komisi: so_ringkas & antrean_gm diubah HANYA lewat penggantian teks "b.pct IS NULL" →
-- "b.perlu_gm" (dan predikat permintaan harga khusus yang menunggu) pada definisi hidup (gagal bila jumlah
-- kemunculannya tidak sesuai), cabang lain tidak disentuh.
-- Tidak ada DROP. Ketiga view tetap security_invoker (diperiksa di akhir).
-- ═══════════════════════════════════════════════════════════════════════

-- ── (6) patokan beku: dibuat_pada diisi sistem saat SP dibuat ──────────────
create or replace function public.isi_dibuat_pada_sp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then new.dibuat_pada := now(); end if;   -- impor/migrasi tanpa sesi: apa adanya
  return new;
end $$;
revoke all on function public.isi_dibuat_pada_sp() from public, anon, authenticated;
create or replace trigger so_a_dibuat_kini
  before insert on public.sales_orders
  for each row execute function public.isi_dibuat_pada_sp();

-- ── (3)+(6) price list per saat SP dibuat, direkonstruksi dari audit_log ──────
-- Keadaan setiap baris price_list (yang masih ada, atau sudah dihapus sesudah p_waktu) pada p_waktu = "sebelum" dari
-- perubahan pertamanya sesudah p_waktu (catat_perubahan menyimpan to_jsonb(old)), atau isinya sekarang bila tidak
-- berubah sejak itu. Yang dipakai: berlaku pada p_tgl dan sudah tercatat pada p_waktu.
create or replace function public.harga_list_pada(p_product bigint, p_tgl date, p_waktu timestamptz)
returns numeric language sql stable security definer set search_path = public as $$
  with calon as (
    select pl.id from public.price_list pl where pl.product_id = p_product
    union
    select a.baris_id from public.audit_log a
     where a.tabel = 'price_list' and a.aksi not in ('INSERT', 'UPDATE') and a.pada > p_waktu
       and a.sebelum ->> 'product_id' = p_product::text
  ), keadaan as (
    select coalesce(
             (select a.sebelum from public.audit_log a
               where a.tabel = 'price_list' and a.baris_id = c.id and a.aksi <> 'INSERT' and a.pada > p_waktu
               order by a.pada, a.id limit 1),
             (select to_jsonb(pl) from public.price_list pl where pl.id = c.id)) as r
      from calon c
  )
  select (k.r ->> 'harga')::numeric
    from keadaan k
   where k.r is not null and k.r ->> 'product_id' = p_product::text
     and (k.r ->> 'berlaku_dari')::date <= p_tgl
     and (k.r ->> 'dibuat_pada')::timestamptz <= p_waktu
   order by (k.r ->> 'berlaku_dari')::date desc, (k.r ->> 'id')::bigint desc
   limit 1
$$;
revoke all on function public.harga_list_pada(bigint, date, timestamptz) from public, anon, authenticated;

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
  -- price list per saat SP DIBUAT: berlaku pada tanggal SP dan sudah tercatat ketika SP dibuat (nilai saat itu)
  new.harga_list := case when new.product_id is null then null
                         else public.harga_list_pada(new.product_id, v_tgl, v_dibuat) end;
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
      cross join lateral (select public.harga_list_pada(l.product_id, s.tanggal, s.dibuat_pada) as harga) x
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
                      AND d.nett_dpp < l.harga_list
                      AND s.no_surat_jalan IS NULL
                      AND NOT (EXISTS ( SELECT 1 FROM so_kirim kk WHERE kk.so_id = s.id))   -- tidak surut ke SP yang sudah dikirim
                      )), false) AS perlu_gm
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
  v_def := replace(v_def, 'b.pct IS NULL', 'b.perlu_gm');
  -- (6) permintaan harga khusus yang menunggu hanya menahan SP pengajunya
  v_n := (length(v_def) - length(replace(v_def, '(h.customer_id = s.customer_id) AND (h.product_id = b.product_id)', '')))
         / length('(h.customer_id = s.customer_id) AND (h.product_id = b.product_id)');
  if v_n <> 1 then
    raise exception '130: antrean_gm memuat predikat harga khusus menunggu % kali (diharapkan 1) — periksa definisinya dulu.', v_n;
  end if;
  v_def := replace(v_def, '(h.customer_id = s.customer_id) AND (h.product_id = b.product_id)',
                          '(h.customer_id = s.customer_id) AND (h.product_id = b.product_id) AND (h.so_id = s.id)');
  execute 'create or replace view public.antrean_gm with (security_invoker = on) as ' || v_def;
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

-- ── (6) persetujuan harga flat tanpa persen gugur bila sales diganti ke non-flat ──────────────────────────
create or replace function public.gugur_setuju_flat_gm()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_lama_flat boolean; v_baru_flat boolean;
begin
  if new.sales_rep_id is not distinct from old.sales_rep_id
     or new.harga_ok is not true or new.gm_pct_harga is not null then
    return new;
  end if;
  select (r.komisi_flat_pct is not null and not coalesce(r.sp_hanya_gm, false)) into v_lama_flat
    from public.sales_reps r where r.id = old.sales_rep_id;
  select (r.komisi_flat_pct is not null) into v_baru_flat
    from public.sales_reps r where r.id = new.sales_rep_id;
  if coalesce(v_lama_flat, false) and not coalesce(v_baru_flat, false)
     and not exists (select 1 from public.komisi_klaim k where k.so_id = new.id) then
    -- GM menyetujui harga tanpa persen karena komisinya flat; untuk sales non-flat persennya harus diputus
    new.harga_ok := null; new.gm_pada := null; new.gm_oleh := null;
  end if;
  return new;
end $$;
revoke all on function public.gugur_setuju_flat_gm() from public, anon, authenticated;
create or replace trigger so_zz_flat_gm_gugur
  before update of sales_rep_id on public.sales_orders
  for each row execute function public.gugur_setuju_flat_gm();

-- ── (6) ajukan_harga_khusus: pengajuan ulang tidak memindahkan so_id dari SP pengaju pertama ──────────────
create or replace function public.ajukan_harga_khusus(p_customer bigint, p_items jsonb, p_alasan text, p_so bigint default null)
returns integer language plpgsql security definer set search_path = public as $$
declare x jsonb; v_n int := 0; v_nett numeric; v_prod bigint; v_ada public.harga_khusus;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengajukan harga khusus.';
  end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Alasan permintaan harga khusus wajib diisi.';
  end if;
  if p_customer is null then
    raise exception 'Harga khusus menempel pada satu perusahaan — pilih customernya dulu.';
  end if;
  if not public.pic_pelanggan_saya(p_customer) then
    raise exception 'Pelanggan ini bukan pelanggan Anda. Harga khusus menempel pada '
                    'perusahaannya, jadi hanya sales yang memegangnya yang boleh '
                    'mengajukan.' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Tidak ada item yang diajukan.';
  end if;

  for x in select * from jsonb_array_elements(p_items) loop
    v_prod := nullif(x->>'product_id', '')::bigint;
    v_nett := nullif(x->>'harga_nett', '')::numeric;
    if v_prod is null then raise exception 'Ada item tanpa product_id.'; end if;
    if v_nett is null or v_nett <= 0 then
      raise exception 'Harga nett untuk item % belum diisi.', v_prod;
    end if;

    select * into v_ada from public.harga_khusus
     where customer_id = p_customer and product_id = v_prod
       and status in ('menunggu','aktif');

    if found and v_ada.status = 'aktif' and v_nett >= v_ada.harga_nett then
      -- Sudah pernah diputuskan dan harganya masih di atas batas. Tidak
      -- perlu antre lagi — itu justru inti fitur ini.
      continue;
    end if;
    if found and v_ada.status = 'menunggu' then
      -- Permintaan yang sama masih menggantung. Harganya diturunkan ke
      -- yang paling rendah supaya GM cukup memutuskan sekali.
      -- 130: so_id SP pengaju PERTAMA dipertahankan — harga khusus yang disetujui berlaku untuk SP pengajunya
      -- (penggolongan beku); dulu pengajuan ulang memindahkannya sehingga SP pengaju pertama tertahan.
      update public.harga_khusus
         set harga_nett = least(harga_nett, v_nett),
             ehc_item   = coalesce(nullif(x->>'ehc_item','')::numeric, ehc_item),
             alasan     = btrim(p_alasan),
             so_id      = coalesce(so_id, p_so),
             diajukan_pada = now(), diajukan_oleh = auth.uid()
       where id = v_ada.id;
      v_n := v_n + 1;
      continue;
    end if;
    if found and v_ada.status = 'aktif' then
      -- Aktif, tapi yang diminta lebih rendah dari batasnya. Yang lama
      -- dinonaktifkan dan diganti permintaan baru — dua baris hidup untuk
      -- pasangan yang sama akan membuat "mana yang berlaku" jadi tebakan.
      update public.harga_khusus set status = 'nonaktif',
             diputus_oleh = auth.uid(), diputus_pada = now()
       where id = v_ada.id;
      insert into public.harga_khusus_log
        (harga_khusus_id, lama_harga, lama_ehc, lama_pct, lama_status,
         harga_nett, ehc_item, komisi_pct, status, catatan, diubah_oleh)
      values (v_ada.id, v_ada.harga_nett, v_ada.ehc_item, v_ada.komisi_pct, 'aktif',
              v_ada.harga_nett, v_ada.ehc_item, v_ada.komisi_pct, 'nonaktif',
              'Diganti permintaan harga yang lebih rendah', auth.uid());
    end if;

    insert into public.harga_khusus
      (customer_id, product_id, harga_nett, ehc_item, alasan, so_id, diajukan_oleh)
    values (p_customer, v_prod, v_nett,
            coalesce(nullif(x->>'ehc_item','')::numeric, 0),
            btrim(p_alasan), p_so, auth.uid());
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

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
