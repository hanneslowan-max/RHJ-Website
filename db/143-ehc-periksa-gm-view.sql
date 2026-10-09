-- ═══════════════════════════════════════════════════════════════════════
-- 143 · EHC tahap 3 (3/3) — VIEW: antrean GM & EHC emergency, hak baca
--       kolom rekening ehc_klaim. Jalankan SESUDAH 141 dan 142 (141 → 142 →
--       143 berturut-turut, boleh satu transaksi). Bila 143 gagal, perbaiki
--       lalu jalankan ulang (idempoten); sesudah 141/142 saja sistem tetap
--       aman (jalur EHC lama tertutup, rekap lama ditolak mesin status).
--
-- WAJIB FE (D3) dirilis SEBELUM berkas ini: bagian 3 mencabut hak baca
-- ehc_klaim.bank/no_rekening/atas_nama, dan PostgREST menolak SELURUH
-- permintaan bila satu kolom tak berhak — EHC_KOLOM tanpa ketiga kolom itu
-- (dan tanpa select=*); rekening dibaca dari embed customer_pics(bank,
-- no_rekening,atas_nama) untuk transfer, sales_rep_rekening (srr_baca) untuk
-- reimburse, ehc_klaim_tujuan sesudah disetujui. Pola KOMISI_KOLOM 139k.
--
-- antrean_gm (dipakai bersama sesi lain: harga/telat/rekening/harga_khusus/
--   ubah/kirim/tanpa_po/transfer). Dibangun dari pg_get_viewdef DEV HIDUP
--   saat dijalankan, dipecah per cabang UNION ALL; hanya cabang EHC yang
--   disentuh, cabang lain dipakai kembali byte-identik:
--   · 'ehc_dini' dibuang (jalur dini sudah digantikan EHC cepat).
--   · 'ehc_cepat': ref_id tetap id klaim; tanggal WIB; pihak = customer
--     penerima (+ "(LINTAS)"); keterangan + keperluan/cara bayar + penanda
--     LINTAS / SP belum lunas; hanya klaim yang masih diajukan.
--   · BARU 'ehc_periksa' (per klaim, mulai tgl 19): ref_id = −id klaim
--     (tameng: index.html lama yang belum mengenal jenis ini menulis ke id
--     negatif, tidak ada SP yang berubah); nomor "EHC #id · no SP";
--     tanggal = cutoff + 1; keterangan nominal · keperluan/cara + penanda
--     LINTAS / SP belum lunas / TANPA LAMPIRAN / cepat ditolak.
--   Kolom & security_invoker tetap; hak akses view tidak diubah.
-- ehc_cepat_siap: hanya klaim yang DISETUJUI jalur cepat dan belum
--   ber-batch; rekening dari ehc_klaim_tujuan (yang dikunci saat GM setuju);
--   kolom lama tetap urut, tambahan di belakang: customer_id, customer,
--   keperluan, lintas_customer, rekening_ada, ada_sp_batal. rekening_ada
--   dari klaim_ehc_tujuan_ada (definer, hanya boolean): true juga untuk
--   Lenni/staff, sementara nomor rekeningnya tetap tersembunyi (ekt_baca).
-- Hak baca kepala ehc_klaim per kolom (bagian 3, prinsip 139k): semua kolom
--   KECUALI bank/no_rekening/atas_nama (salinan simpan_klaim_ehc; reimburse
--   = rekening pribadi sales). Kolom baru ehc_klaim kelak WAJIB di-grant
--   select per kolom di migrasinya sendiri (hak per kolom tidak otomatis).
--
-- Keputusan Hannes 9 Okt 2026: P1 (GM boleh memutus klaim sendiri — tidak
-- ada penanda "terlibat" di antrean), P2 (cepat ditolak → klaim tetap
-- diajukan, muncul di 'ehc_periksa' dengan penanda "cepat ditolak"),
-- P4 (antrean membaca ehc_klaim dengan hak pembaca — Vonny/Lie Sian/Ichi
-- tidak melihat baris EHC).
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1. antrean_gm ────────────────────────────────────────────────────────
do $$
declare
  v_def    text;
  v_bag    text[];
  v_hasil  text[] := '{}';
  b        text;
  v_jenis  text;
  v_dini   integer := 0;
  v_cepat  integer := 0;
  v_periksa integer := 0;
  v_cabang_cepat text := $c$ SELECT 'ehc_cepat'::text AS jenis,
    k.id AS ref_id,
    COALESCE(s.no_sp, ('#'::text || k.id)) AS nomor,
    (COALESCE(c.nama, s.kepada, '-'::text) || CASE WHEN public.klaim_ehc_lintas(k.id) THEN ' (LINTAS)'::text ELSE ''::text END) AS pihak,
    k.sales_rep_id,
    COALESCE(((k.cepat_diminta_pada AT TIME ZONE 'Asia/Jakarta'::text))::date, k.tanggal) AS tanggal,
    ('Minta EHC dicairkan cepat - '::text || COALESCE(public.rp_teks(n.nominal), '-'::text) || ' · '::text
      || k.keperluan || '/'::text || k.cara_bayar
      || CASE WHEN public.klaim_ehc_lintas(k.id) THEN ' · LINTAS'::text ELSE ''::text END
      || CASE WHEN EXISTS (SELECT 1 FROM public.ehc_klaim_alokasi a JOIN public.sales_orders so ON so.id = a.so_id
                            WHERE a.klaim_id = k.id AND a.nominal > 0 AND NOT so.lunas) THEN ' · SP belum lunas'::text ELSE ''::text END
      || ' - '::text || "left"(COALESCE(k.cepat_alasan, 'tanpa alasan'::text), 80)) AS keterangan,
    k.so_id
   FROM (((public.ehc_klaim k
     LEFT JOIN public.sales_orders s ON ((s.id = k.so_id)))
     LEFT JOIN public.customers c ON ((c.id = k.customer_id)))
     LEFT JOIN public.ehc_klaim_nilai n ON ((n.klaim_id = k.id)))
  WHERE (k.cepat_minta AND (k.cepat_ok IS NULL) AND (k.transfer_batch_id IS NULL) AND (k.status = 'diajukan'::text))$c$;
  v_cabang_periksa text := $c$ SELECT 'ehc_periksa'::text AS jenis,
    (- k.id) AS ref_id,
    (('EHC #'::text || k.id) || COALESCE((' · '::text || s.no_sp), ''::text)) AS nomor,
    (COALESCE(c.nama, '-'::text) || CASE WHEN public.klaim_ehc_lintas(k.id) THEN ' (LINTAS)'::text ELSE ''::text END) AS pihak,
    k.sales_rep_id,
    (public.cutoff_ehc(k.periode) + 1) AS tanggal,
    ('Periksa EHC periode '::text || k.periode || ' — '::text || COALESCE(public.rp_teks(n.nominal), '-'::text)
      || ' · '::text || k.keperluan || '/'::text || k.cara_bayar
      || CASE WHEN public.klaim_ehc_lintas(k.id) THEN ' · LINTAS'::text ELSE ''::text END
      || CASE WHEN EXISTS (SELECT 1 FROM public.ehc_klaim_alokasi a JOIN public.sales_orders so ON so.id = a.so_id
                            WHERE a.klaim_id = k.id AND a.nominal > 0 AND NOT so.lunas) THEN ' · SP belum lunas'::text ELSE ''::text END
      || CASE WHEN NOT EXISTS (SELECT 1 FROM public.ehc_klaim_berkas f
                                WHERE f.klaim_id = k.id AND f.dibuang_pada IS NULL) THEN ' · TANPA LAMPIRAN'::text ELSE ''::text END
      || CASE WHEN k.cepat_minta AND k.cepat_ok = false THEN ' · cepat ditolak'::text ELSE ''::text END) AS keterangan,
    k.so_id
   FROM (((public.ehc_klaim k
     LEFT JOIN public.sales_orders s ON ((s.id = k.so_id)))
     LEFT JOIN public.customers c ON ((c.id = k.customer_id)))
     LEFT JOIN public.ehc_klaim_nilai n ON ((n.klaim_id = k.id)))
  WHERE ((k.status = 'diajukan'::text) AND (k.transfer_batch_id IS NULL)
         AND (public.hari_ini_wib() > public.cutoff_ehc(k.periode))
         AND (NOT (k.cepat_minta AND (k.cepat_ok IS NULL))))$c$;
begin
  v_def := btrim(pg_get_viewdef('public.antrean_gm'::regclass));
  v_def := rtrim(v_def, ';');
  v_bag := string_to_array(v_def, E'\nUNION ALL\n');
  foreach b in array v_bag loop
    v_jenis := substring(b from '^\s*SELECT ''([a-z_]+)''::text AS jenis');
    if v_jenis is null then
      raise exception '143: ada cabang antrean_gm yang jenisnya tidak terbaca: %', left(b, 120);
    end if;
    if v_jenis = 'ehc_dini' then
      v_dini := v_dini + 1;
    elsif v_jenis = 'ehc_cepat' then
      v_cepat := v_cepat + 1;
      v_hasil := v_hasil || v_cabang_cepat;
    elsif v_jenis = 'ehc_periksa' then
      v_periksa := v_periksa + 1;
    else
      v_hasil := v_hasil || b;
    end if;
  end loop;
  if v_cepat <> 1 or v_dini + v_periksa <> 1 then
    raise exception '143: cabang EHC antrean_gm tidak sesuai harapan (ehc_cepat %, ehc_dini %, ehc_periksa %) — definisi DEV berubah, periksa manual.',
      v_cepat, v_dini, v_periksa;
  end if;
  v_hasil := v_hasil || v_cabang_periksa;
  execute 'create or replace view public.antrean_gm with (security_invoker = on) as '
       || array_to_string(v_hasil, E'\nUNION ALL\n');
end $$;

-- ── 2. ehc_cepat_siap ────────────────────────────────────────────────────
-- Penanda "rekening tujuan sudah terkunci" untuk semua pembaca klaim
-- (Lenni/staff juga), tanpa membuka nomor rekeningnya: ekt_baca tetap
-- owner/GM/finance/sales pemilik, fungsi ini hanya mengembalikan boolean.
create or replace function public.klaim_ehc_tujuan_ada(p_klaim bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select (public.boleh_lihat_nilai_klaim() or public.klaim_ehc_saya(p_klaim))
     and exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = p_klaim)
$$;
revoke all on function public.klaim_ehc_tujuan_ada(bigint) from public, anon;
grant execute on function public.klaim_ehc_tujuan_ada(bigint) to authenticated;

create or replace view public.ehc_cepat_siap with (security_invoker = on) as
select k.id as klaim_id,
       k.so_id,
       s.no_sp,
       s.kepada,
       k.sales_rep_id,
       r.nama as sales,
       p.nama as pic,
       k.cara_bayar,
       t.bank,
       t.no_rekening,
       t.atas_nama,
       k.tanggal,
       n.nominal,
       k.cepat_alasan,
       k.cepat_catatan,
       k.cepat_diputus_pada,
       public.klaim_ehc_terkunci_pengajuan(k.id) as pengajuan_bulanan,
       k.customer_id,
       c.nama as customer,
       k.keperluan,
       public.klaim_ehc_lintas(k.id) as lintas_customer,
       public.klaim_ehc_tujuan_ada(k.id) as rekening_ada,
       exists (select 1 from public.ehc_klaim_alokasi a join public.sales_orders so on so.id = a.so_id
                where a.klaim_id = k.id and a.nominal > 0 and so.batal) as ada_sp_batal
  from public.ehc_klaim k
  left join public.sales_orders s on s.id = k.so_id
  left join public.sales_reps r on r.id = k.sales_rep_id
  left join public.customer_pics p on p.id = k.pic_id
  left join public.ehc_klaim_nilai n on n.klaim_id = k.id
  left join public.customers c on c.id = k.customer_id
  left join public.ehc_klaim_tujuan t on t.klaim_id = k.id
 where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null;
revoke all on public.ehc_cepat_siap from anon;

-- ── 3. hak baca kolom rekening di kepala ehc_klaim ───────────────────────
-- Harus SESUDAH ehc_cepat_siap dibangun ulang dari ehc_klaim_tujuan (versi
-- lama view invoker itu membaca k.bank/no_rekening/atas_nama dan akan rusak
-- 42501). Fungsi definer (simpan_klaim_ehc dll.) tidak terpengaruh; view
-- invoker ehc_saldo_sp, sales_beban, ehc_belum_klaim, antrean_gm tidak
-- membaca ketiga kolom itu. Idempoten: REVOKE tingkat tabel ikut mencabut
-- hak per kolom, lalu kolom yang boleh di-grant ulang.
do $$
declare v_kol text;
begin
  revoke select on public.ehc_klaim from public, anon, authenticated;
  select string_agg(quote_ident(column_name::text), ', ' order by ordinal_position) into v_kol
    from information_schema.columns
   where table_schema = 'public' and table_name = 'ehc_klaim'
     and column_name not in ('bank','no_rekening','atas_nama');
  execute 'grant select (' || v_kol || ') on public.ehc_klaim to authenticated';
  if has_column_privilege('authenticated', 'public.ehc_klaim', 'bank', 'select')
     or has_column_privilege('authenticated', 'public.ehc_klaim', 'no_rekening', 'select')
     or has_column_privilege('authenticated', 'public.ehc_klaim', 'atas_nama', 'select')
     or has_column_privilege('anon', 'public.ehc_klaim', 'id', 'select')
     or not has_column_privilege('authenticated', 'public.ehc_klaim', 'gm_pada', 'select')
     or not has_column_privilege('authenticated', 'public.ehc_klaim', 'ditransfer_pada', 'select')
     or not has_column_privilege('authenticated', 'public.ehc_klaim', 'cepat_diminta_pada', 'select') then
    raise exception '143: hak baca kolom ehc_klaim tidak sesuai harapan — periksa manual.';
  end if;
end $$;
