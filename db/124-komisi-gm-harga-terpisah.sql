-- ═══════════════════════════════════════════════════════════════════════
-- 124 · perbaikan hasil review #50/#51
--
-- (1) #51 · persen GM untuk HARGA dipisah dari persen GM untuk TELAT.
--     Satu kolom sales_orders.gm_pct dipakai dua keputusan: persetujuan harga (#51: kini WAJIB diisi) dan
--     invoice telat >120 hari (komisi_hitung = total_barang × gm_pct untuk seluruh SP; antrean_gm 'telat'
--     hanya muncul bila gm_pct kosong). Akibatnya setiap SP yang harganya disetujui tidak pernah lagi masuk
--     antrean telat, dan bila telat komisinya diam-diam memakai persen harga untuk SELURUH SP (bisa Rp 0
--     atau melonjak) lalu beku saat diklaim (uji review: SP 020/IX 0% → klaim Rp 0; 009/IX 17% → +2,76 jt).
--     Sekarang: kolom baru gm_pct_harga = persen GM untuk baris di bawah / tanpa price list (dibaca
--     so_baris_hitung.pct_berlaku, ditulis laci keputusan 'harga'); gm_pct kembali KHUSUS persen telat
--     (antrean_gm, komisi_hitung, jaga_gerbang_komisi, komisi_belum_klaim tidak diubah — objek sesi EHC/komisi).
--     Data: gm_pct_harga diisi dari gm_pct untuk SP yang harganya sudah disetujui → angka komisi #51 tidak
--     bergeser. gm_pct SP lama TIDAK dikosongkan (kolom itu dijaga jaga_kolom_sales; dan maknanya bagi SP yang
--     sudah telat perlu keputusan Hannes) — SP lama tetap berperilaku seperti sebelum #51 bila kelak telat.
--     gm_pct_harga hanya boleh diisi GM/owner (penjaga sendiri, sama dengan jaga_kolom_sales bagian d) dan
--     dibatasi 0–50%.
-- (2) #51 · so_baris_hitung: OFFSET 0 pada LATERAL k supaya komisi_pct_baris dihitung SEKALI per baris (tanpa
--     itu subquery ditarik naik dan fungsi dipanggil 3× per baris — so_ringkas ±2,5× lebih lambat). Angka sama.
-- (3) #51 · komisi_sp_saya.menunggu_gm hanya bila harga BELUM diputus (harga_ok null) — SP yang harganya
--     ditolak GM tidak lagi ditulis "menunggu GM" (layar membedakannya lewat harga_ok).
-- (4) #50 · HP wajib tidak bisa dilangkahi lewat batal → dipulihkan: trigger ikut menyala pada perubahan batal,
--     dan SP batal yang dihidupkan lagi diperiksa seperti SP baru.
--
-- Tidak ada DROP. Kedua view tetap security_invoker (diperiksa di akhir).
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) kolom persen GM untuk harga ─────────────────────────────────────
alter table public.sales_orders add column if not exists gm_pct_harga numeric(6,4);
comment on column public.sales_orders.gm_pct_harga is
  'Persen komisi dari GM untuk baris di bawah / tanpa price list (#51, berkas 124). Bukan persen telat (gm_pct).';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'so_gm_pct_harga_wajar' and conrelid = 'public.sales_orders'::regclass) then
    alter table public.sales_orders add constraint so_gm_pct_harga_wajar
      check (gm_pct_harga is null or (gm_pct_harga >= 0 and gm_pct_harga <= 0.5));
  end if;
end $$;

create or replace function public.jaga_gm_pct_harga()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.boleh_approve() then return new; end if;   -- sistem/migrasi, GM, owner
  if (tg_op = 'INSERT' and new.gm_pct_harga is not null)
     or (tg_op = 'UPDATE' and new.gm_pct_harga is distinct from old.gm_pct_harga) then
    raise exception 'Peran Anda (%) tidak boleh mengisi persentase komisi GM pada Surat Pesanan %. Kolom itu wewenang GM atau owner.',
      public.peran_saya(), coalesce(new.no_sp, '(baru)') using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_gm_pct_harga() from public, anon, authenticated;
create or replace trigger so_jaga_gm_pct_harga
  before insert or update of gm_pct_harga on public.sales_orders
  for each row execute function public.jaga_gm_pct_harga();

-- angka komisi #51 tidak bergeser: persen yang sudah dipakai untuk baris di bawah list pindah ke kolom baru
update public.sales_orders set gm_pct_harga = gm_pct
 where harga_ok is true and gm_pct is not null and gm_pct_harga is null;

-- ── (1)+(2) so_baris_hitung ─────────────────────────────────────────────
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
            WHEN (s.harga_ok IS TRUE) THEN COALESCE(s.gm_pct_harga, (0)::numeric)
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
     -- OFFSET 0 SENGAJA: mencegah subquery ditarik naik → komisi_pct_baris dihitung sekali per baris. Jangan dihapus.
     CROSS JOIN LATERAL ( SELECT komisi_pct_baris(l.jenis, rep.komisi_flat_pct, (hk.id IS NOT NULL), hk.komisi_pct, s.cash_ok, d.nett_dpp,
            COALESCE(l.harga_list, harga_berlaku(l.product_id)), (upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text)) AS pct
         OFFSET 0) k)
  WHERE ((COALESCE(l.batal, false) = false) AND ((l.qty - l.qty_batal) > (0)::numeric));

-- ── (3) komisi_sp_saya: "menunggu GM" hanya bila harga belum diputus ─────
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
           coalesce(r.ada_bawah_list, false) and s.harga_ok is null and not s.batal,
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

-- ── (4) #50 · HP wajib: SP batal yang dihidupkan lagi diperiksa seperti SP baru ──
create or replace function public.jaga_hp_sp_tanpa_pelanggan()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_hp text;
begin
  if new.batal or new.customer_id is not null then return new; end if;
  if tg_op = 'UPDATE' and not old.batal and old.customer_id is null
     and public.hp_baku(new.telp) is not distinct from public.hp_baku(old.telp) then
    return new;   -- SP lama: No. HP tidak diubah → tidak diperiksa (yang kosong tetap boleh diubah hal lain)
  end if;
  v_hp := public.hp_baku(new.telp);
  if v_hp is null then
    if new.po_id is not null then
      raise exception 'No. HP pelanggan wajib diisi pada Surat Pesanan % karena PO-nya belum tertaut ke data pelanggan. Isi satu No. HP yang bisa dihubungi (mis. 0812xxxxxxx) — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek.',
        coalesce(new.no_sp, '(baru)') using errcode = '23502';
    end if;
    raise exception 'No. HP pelanggan wajib diisi pada Surat Pesanan % karena pelanggannya belum dipilih dari data pelanggan. Isi satu No. HP yang bisa dihubungi (mis. 0812xxxxxxx) — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek — atau pilih pelanggannya dari daftar.',
      coalesce(new.no_sp, '(baru)') using errcode = '23502';
  end if;
  if v_hp !~ '^[1-9][0-9]{8,15}$' then
    raise exception 'No. HP "%" pada Surat Pesanan % tidak valid — isi satu nomor, 9 sampai 16 angka, mis. 0812xxxxxxx.',
      new.telp, coalesce(new.no_sp, '(baru)') using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public.jaga_hp_sp_tanpa_pelanggan() from public, anon, authenticated;
create or replace trigger so_yy_hp_wajib
  before insert or update of customer_id, telp, batal on public.sales_orders
  for each row execute function public.jaga_hp_sp_tanpa_pelanggan();

-- ── pemeriksaan: view tetap security_invoker (RLS) ──────────────────────
do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relname in ('so_baris_hitung', 'so_ringkas')
                and not coalesce(c.reloptions, '{}') @> array['security_invoker=on']) then
    raise exception 'so_baris_hitung / so_ringkas kehilangan security_invoker — migrasi dibatalkan.';
  end if;
end $$;
