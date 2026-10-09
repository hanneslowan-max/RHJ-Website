-- ═══════════════════════════════════════════════════════════════════════
-- 136c · Review adversarial berkas 136 (temuan "bocor"): laporan & harga khusus mengikuti aturan baca SP (berkas 83)
--
-- Celah (uji DEV, rollback; sudah ada sebelum 136, ditemukan saat memeriksa 136): aturan baca SP berkas 83 — SP yang
-- masih menunggu cek Vonny (tidak batal, belum ada surat jalan, vonny_ok belum true) hanya terbaca owner, GM, Vonny,
-- sales pemiliknya, dan pembuatnya — dilompati di tiga jalur:
--  · laporan_penjualan (potongan produk, kategori, sales, pelanggan), laporan_margin_produk, laporan_margin_sp:
--    SECURITY DEFINER milik postgres (lewat RLS) dan hanya menyaring "not batal" + saringan rep untuk sales. Staff,
--    finance, Lie Sian, Ichi, Lenni membaca barang/usulan item, qty, nilai, dan pelanggan SP yang menunggu cek Vonny;
--    finance di laporan_margin_sp bahkan melihat nomor SP, Kepada, sales, dan statusnya. Uji: usulan "UJI136 LAP B" di
--    SP 168 (menunggu vonny) — staff/finance/liesian/ichi/lenni: /sales_orders 0 baris, laporan 1 SP qty 7.
--  · view harga_khusus_lengkap (milik postgres, tanpa security_invoker): no_sp dan dipakai_baris dihitung dari SEMUA
--    SP (termasuk SP sales lain dan SP menunggu cek Vonny). Hak bawaan anon/authenticated juga penuh.
--
-- Perbaikan:
--  (1) sp_terbaca(rep, dibuat_oleh, batal, no_surat_jalan, vonny_ok): ekspresi so_baca yang SAMA PERSIS (berkas 83 +
--      cabang pembuat), fungsi SQL biasa (bukan SECURITY DEFINER, tanpa SET) supaya di-inline planner dan
--      peran_saya() dkk. dihitung sekali per query. Bila so_baca diubah, fungsi ini WAJIB ikut diubah.
--  (2) Ketiga laporan menambahkan "and public.sp_terbaca(...)" pada setiap pemindaian SP (ganti teks pada definisi
--      hidup dengan pemeriksaan jumlah jangkar; tanda tangan, SECURITY DEFINER, dan isi lain tidak berubah — tidak
--      dijadikan invoker karena Lie Sian/Ichi tidak lolos boleh_baca customers/sales_reps, nama pelanggan/sales akan
--      hilang dari laporannya). Owner/GM/Vonny & sales (laporan miliknya) tidak berubah.
--  (3) harga_khusus_lengkap dibuat ulang dengan security_invoker = on (isi sama persis, dari pg_get_viewdef): no_sp dan
--      dipakai_baris hanya dari SP yang boleh dibaca pembacanya. Kolom lain tidak berubah: peran yang lolos saringan
--      view (boleh_baca + pic_pelanggan_saya) juga lolos RLS harga_khusus, customers, dan products. anon tanpa hak,
--      authenticated hanya SELECT. PERINGATAN: berkas 115 membuat ulang view ini tanpa klausa invoker — setiap
--      "create or replace view harga_khusus_lengkap" berikutnya WAJIB membawa "with (security_invoker = on)".
-- Akibat yang terlihat (dicatat di ATURAN B): selama ada SP menunggu cek Vonny, angka laporan staff/finance/Lie Sian/
-- Ichi/Lenni lebih kecil daripada angka owner/GM/Vonny; SP itu masuk laporan mereka sesudah dicek Vonny.
-- Tidak menyentuh objek EHC/komisi (laporan_komisi tidak diubah). Tidak ada data yang diubah; tidak ada objek dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- (1)
create or replace function public.sp_terbaca(p_rep bigint, p_dibuat_oleh uuid, p_batal boolean, p_no_sj text,
                                             p_vonny_ok boolean)
returns boolean language sql stable as $$
  -- cermin RLS so_baca (berkas 83): ubah bersama-sama
  select coalesce(
           ((select public.peran_saya()) = 'sales' and p_rep = (select public.sales_rep_saya()))
           or case when not p_batal and p_no_sj is null and not coalesce(p_vonny_ok, false)
                   then (select public.peran_saya()) in ('owner','gm','vonny')
                        or (p_dibuat_oleh = (select auth.uid()) and (select public.boleh_alur_jual()))
                   else (select public.boleh_lihat_semua_jual())
              end, false)
$$;
comment on function public.sp_terbaca(bigint, uuid, boolean, text, boolean) is
  '136c: aturan baca SP (RLS so_baca, berkas 83) untuk fungsi SECURITY DEFINER yang memindai sales_orders — wajib sama dengan so_baca.';
revoke all on function public.sp_terbaca(bigint, uuid, boolean, text, boolean) from public, anon;
grant execute on function public.sp_terbaca(bigint, uuid, boolean, text, boolean) to authenticated;

-- (2)
do $$
declare
  v text; w text;
  a text := 'and (v_rep is null or s.sales_rep_id = v_rep)';
  b text := $b$where not s.batal
       and not l.batal$b$;
  f regprocedure;
begin
  v := pg_get_functiondef('public.laporan_penjualan(date, date, text)'::regprocedure);
  if position('sp_terbaca' in v) = 0 then
    if (length(v) - length(replace(v, a, ''))) / length(a) <> 3 then
      raise exception '136c: laporan_penjualan — jangkar saringan rep tidak 3 (bentuk berubah, periksa manual).';
    end if;
    w := replace(v, a, a || ' and public.sp_terbaca(s.sales_rep_id, s.dibuat_oleh, s.batal, s.no_surat_jalan, s.vonny_ok)   -- 136c');
    execute w;
  end if;

  foreach f in array array['public.laporan_margin_produk(date,date)'::regprocedure,
                           'public.laporan_margin_sp(date,date)'::regprocedure] loop
    v := pg_get_functiondef(f);
    if position('sp_terbaca' in v) = 0 then
      if (length(v) - length(replace(v, b, ''))) / length(b) <> 1 then
        raise exception '136c: % — jangkar "where not s.batal / and not l.batal" tidak 1 (periksa manual).', f;
      end if;
      w := replace(v, b, $c$where not s.batal
       and public.sp_terbaca(s.sales_rep_id, s.dibuat_oleh, s.batal, s.no_surat_jalan, s.vonny_ok)   -- 136c
       and not l.batal$c$);
      execute w;
    end if;
  end loop;
end $$;

-- (3)
do $$
declare w text := pg_get_viewdef('public.harga_khusus_lengkap'::regclass, true);
begin
  execute 'create or replace view public.harga_khusus_lengkap with (security_invoker = on) as ' || w;
end $$;
revoke all on public.harga_khusus_lengkap from public, anon, authenticated;
grant select on public.harga_khusus_lengkap to authenticated;

do $$
declare n int;
begin
  select (length(d) - length(replace(d, 'sp_terbaca', ''))) / length('sp_terbaca') into n
    from (select pg_get_functiondef('public.laporan_penjualan(date, date, text)'::regprocedure) d) x;
  if n <> 3 then raise exception '136c: laporan_penjualan belum memakai sp_terbaca di 3 cabang (%).', n; end if;
  if position('sp_terbaca' in pg_get_functiondef('public.laporan_margin_produk(date,date)'::regprocedure)) = 0
     or position('sp_terbaca' in pg_get_functiondef('public.laporan_margin_sp(date,date)'::regprocedure)) = 0 then
    raise exception '136c: laporan margin belum memakai sp_terbaca';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.harga_khusus_lengkap'::regclass
                    and coalesce(reloptions::text[] @> array['security_invoker=on'], false))
     or has_table_privilege('anon', 'public.harga_khusus_lengkap', 'select')
     or has_table_privilege('authenticated', 'public.harga_khusus_lengkap', 'insert') then
    raise exception '136c: harga_khusus_lengkap belum security_invoker / hak belum dipersempit';
  end if;
end $$;
