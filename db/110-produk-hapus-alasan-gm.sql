-- ═══════════════════════════════════════════════════════════════════════
-- 110 · Produk (#32 #33)
--
--  #32  hapus_produk(p_id) — hanya owner (boleh_hapus). Produk yang BELUM pernah
--       dipakai (PO, SP, penawaran, lead, set roda, order impor, harga khusus)
--       dihapus permanen: price list, HPP manual, nilai edit massal, dan
--       spesifikasi sales-nya ikut terhapus (FK cascade), kode pabrik yang
--       tersambung DILEPAS (product_id = NULL), tidak dihapus. Yang SUDAH dipakai
--       tidak dihapus — dinonaktifkan (aktif = false), riwayatnya utuh.
--  #33  Baris SP tanpa price list (mis. produk baru/usulan) dulu dilaporkan
--       "Harga di bawah price list" — komisi_tier() memang mengembalikan NULL untuk
--       keduanya dan gerbang GM-nya sama. Sekarang dibedakan: so_ringkas mendapat
--       n_bawah_list & n_tanpa_list (kolom ditambah di ujung; kolom lama tidak
--       berubah), dan antrean_gm menuliskan alasan yang sebenarnya.
--       Gerbangnya TIDAK berubah: ada_bawah_list (pct NULL) tetap menahan SP ke GM.
--
-- Tidak ada data yang dihapus oleh migrasi ini.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) #32 ──────────────────────────────────────────────────────────────
create or replace function public.hapus_produk(p_id bigint)
returns text
language plpgsql security definer set search_path = public as $$
declare v_kode text; v_pakai text;
begin
  if not public.boleh_hapus() then
    raise exception 'Hanya owner yang bisa menghapus produk.' using errcode = '42501';
  end if;
  select kode into v_kode from public.products where id = p_id;
  if v_kode is null then raise exception 'Produk #% tidak ditemukan.', p_id using errcode = 'P0002'; end if;
  select string_agg(x, ', ') into v_pakai from (
              select 'PO' as x          where exists (select 1 from public.po_lines               where product_id = p_id)
    union all select 'SP'               where exists (select 1 from public.sales_order_lines      where product_id = p_id)
    union all select 'penawaran'        where exists (select 1 from public.quote_lines            where product_id = p_id)
    union all select 'lead'             where exists (select 1 from public.leads                  where product_id = p_id)
    union all select 'set roda'         where exists (select 1 from public.product_set_components where product_id = p_id)
    union all select 'order impor'      where exists (select 1 from public.import_lines           where product_id = p_id)
    union all select 'harga khusus'     where exists (select 1 from public.harga_khusus           where product_id = p_id)
  ) t;
  if v_pakai is not null then
    update public.products set aktif = false where id = p_id and aktif;
    return 'Produk ' || v_kode || ' sudah dipakai di ' || v_pakai
        || ' — tidak dihapus, tetapi dinonaktifkan: tidak muncul lagi di pilihan barang, riwayatnya tetap utuh.';
  end if;
  update public.factory_codes set product_id = null where product_id = p_id;   -- dilepas, tidak dihapus
  delete from public.products where id = p_id;                                -- price_list dkk. ikut (cascade)
  return 'Produk ' || v_kode || ' dihapus permanen (belum pernah dipakai transaksi).';
end $$;
revoke all on function public.hapus_produk(bigint) from public, anon;
grant execute on function public.hapus_produk(bigint) to authenticated;

-- ── (2) #33 so_ringkas: dua hitungan baru di ujung ───────────────────────
-- WITH (security_invoker) WAJIB ditulis ulang: CREATE OR REPLACE VIEW mengganti opsi view.
create or replace view public.so_ringkas with (security_invoker = on) as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.sales_rep_id,
    s.ppn_kena,
    s.status,
    COALESCE(sum(b.nilai_barang) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) AS total_barang,
    COALESCE(sum(b.nilai_ehc), 0::numeric) AS total_ehc,
    COALESCE(sum(b.nilai_baris), 0::numeric) AS sub_total,
        CASE
            WHEN s.ppn_kena THEN COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) * 0.11
            ELSE 0::numeric
        END AS ppn,
    COALESCE(sum(b.nilai_baris), 0::numeric) +
        CASE
            WHEN s.ppn_kena THEN COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) * 0.11
            ELSE 0::numeric
        END AS grand_total,
    COALESCE(sum(b.nilai_barang * b.pct) FILTER (WHERE b.pct IS NOT NULL), 0::numeric) AS komisi,
    COALESCE(bool_or(b.pct IS NULL) FILTER (WHERE b.id IS NOT NULL AND b.jenis = 'barang'::text), false) AS ada_bawah_list,
    count(b.id) AS jumlah_baris,
    COALESCE(sum(b.nilai_barang) FILTER (WHERE b.jenis = 'biaya'::text), 0::numeric) AS total_biaya,
    COALESCE(sum(b.nilai_baris) FILTER (WHERE b.jenis = 'barang'::text), 0::numeric) AS dasar_ppn,
    -- #33 (berkas 110): alasan pct NULL dipisah
    count(b.id) FILTER (WHERE b.jenis = 'barang'::text AND b.pct IS NULL AND COALESCE(b.harga_list, 0::numeric) > 0::numeric) AS n_bawah_list,
    count(b.id) FILTER (WHERE b.jenis = 'barang'::text AND b.pct IS NULL AND COALESCE(b.harga_list, 0::numeric) <= 0::numeric) AS n_tanpa_list
   FROM sales_orders s
     LEFT JOIN so_baris_hitung b ON b.so_id = s.id
  GROUP BY s.id;

-- ── (3) #33 antrean_gm: keterangan 'harga' menyebut alasan sebenarnya ────
do $$
declare v text; lama text := '''Harga di bawah price list''::text AS keterangan';
begin
  v := pg_get_viewdef('public.antrean_gm'::regclass, true);
  if position(lama in v) = 0 then
    raise exception 'antrean_gm tidak berbentuk seperti yang diharapkan — keterangan harga tidak ditemukan.';
  end if;
  v := replace(v, lama,
    'CASE WHEN r.n_tanpa_list > 0 AND r.n_bawah_list = 0 THEN ''Belum ada price list (produk baru/usulan) — komisi menunggu keputusan GM''::text '
    || 'WHEN r.n_tanpa_list > 0 THEN ''Harga di bawah price list + ada produk tanpa price list''::text '
    || 'ELSE ''Harga di bawah price list''::text END AS keterangan');
  execute 'create or replace view public.antrean_gm with (security_invoker = on) as ' || v;
end $$;
