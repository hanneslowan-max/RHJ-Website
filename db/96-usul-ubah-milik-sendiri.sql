-- Berkas 96 (#1 #6 #7, temuan review keamanan-data kelompok PO set/diskon): usulan ubah PO hanya untuk
-- PO milik sendiri (sales), dan usulan ubah hanya terbaca oleh yang bisa membaca dokumennya.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026 (migrasi 96_usul_ubah_milik_sendiri).
-- Belum ke produksi (sesudah berkas 94 —
-- badan ajukan_ubah di sini = badan berkas 94 + satu cek).
--
-- Masalah (celah lama, bukan regresi berkas 94; terverifikasi di DEV dengan uji rollback):
--   (1) ajukan_ubah cabang 'po' (SECURITY DEFINER) hanya memeriksa boleh_input_po(), tanpa cek
--       pemilik — padahal cabang 'sp' sudah punya cek "SP milik sendiri". Sales Alfred (rep 2), yang
--       TIDAK bisa membaca PO 60 (milik rep 6; select → 0 baris), berhasil ajukan_ubah('po', 60, …):
--       nilai_lama menyimpan PO utuh (nama_customer, harga, keterangan) dan sejak berkas 94 nilai_baru
--       juga dilengkapi dari baris tersimpan. Usulan asal-asalan itu sekaligus MENGUNCI PO sales lain:
--       indeks unik uu_menunggu_uniq (jenis, ref_id) where status='menunggu' menolak usulan asli sampai
--       GM menolak yang palsu.
--   (2) Policy uu_baca = boleh_lihat_semua_jual() OR boleh_alur_jual() OR diajukan_oleh = auth.uid().
--       boleh_alur_jual() memuat 'sales' → SETIAP sales membaca SEMUA usulan (nilai_lama/nilai_baru =
--       isi PO/SP sales lain). Uji: Alfred membaca usulan #3–#8 (PO 32/42/55 & SP 51 milik rep 3/5/8/9).
--       Selain itu boleh_lihat_semua_jual() (staff, finance, liesian, ichi, lenni) membaca usulan atas
--       SP yang masih menunggu cek Vonny, padahal SP-nya sendiri disembunyikan so_baca (berkas 83/88).
--
-- Perubahan (tanpa perubahan tabel/kolom/data):
--   (1) ajukan_ubah cabang 'po': sales hanya untuk PO dengan sales_rep_id = sales_rep_saya()
--       (errcode 42501, pola sama dengan cabang 'sp'). Peran lain di boleh_input_po() (owner, gm,
--       staff, vonny) memang membaca semua PO (po_baca) → tidak berubah. Sisa badan = berkas 94.
--   (2) uu_baca: usulan terbaca bila dokumennya terbaca oleh pembaca itu — EXISTS ke purchase_orders /
--       sales_orders yang tunduk pada RLS po_baca / so_baca pembaca (pola sama dengan pol_baca di
--       po_lines) — atau pembaca owner/GM (setara_owner; agar usulan atas dokumen yang sudah dihapus
--       tetap bisa diputus). Hak baca usulan jadi selalu ikut hak baca dokumennya, termasuk bila so_baca
--       diubah lagi kelak. Klausa diajukan_oleh = auth.uid() DIHAPUS: satu-satunya kasus ia menambah
--       hak adalah pengaju yang tidak bisa membaca dokumennya (dokumen sudah dipindah ke sales lain,
--       atau staff mengajukan atas SP menunggu Vonny yang tersembunyi) — justru jalur bocornya.
--       FE hanya membaca usulan 'menunggu' untuk penanda di daftar PO/SP & detail GM → tidak terdampak.
--       View antrean_gm (security_invoker) ikut tersaring otomatis.
--
-- Tidak diubah (dicatat untuk Hannes): cabang 'sp' untuk staff — staff masih bisa MENGAJUKAN usulan atas
-- SP menunggu Vonny buatan orang lain (tidak bisa membacanya lagi sesudah berkas ini). Menutupnya berarti
-- menyalin syarat so_baca ke fungsi (rawan beda bila so_baca diubah kelompok #8); GM tetap memutuskan.
--
-- Membalik:
--   alter policy uu_baca on public.usul_ubah using
--     (boleh_lihat_semua_jual() OR boleh_alur_jual() OR (diajukan_oleh = auth.uid()));
--   create or replace ajukan_ubah dengan badan berkas 94 (hapus blok "Sales hanya boleh mengajukan
--   untuk PO miliknya sendiri").

-- 1) ajukan_ubah — cabang po: cek pemilik untuk sales (badan lain = berkas 94)
create or replace function public.ajukan_ubah(p_jenis text, p_ref bigint, p_baru jsonb, p_alasan text)
returns bigint language plpgsql security definer set search_path to 'public' as $function$
declare v_lama jsonb; v_id bigint;
begin
  if p_jenis not in ('po','sp') then
    raise exception 'Jenis usulan harus po atau sp.';
  end if;
  if coalesce(btrim(p_alasan), '') = '' or length(btrim(p_alasan)) < 5 then
    raise exception 'Alasan perubahan harus diisi — GM memutuskan dari alasannya, '
                    'bukan dari angkanya saja.';
  end if;

  if p_jenis = 'po' then
    if not public.boleh_input_po() then
      raise exception 'Anda tidak berwenang mengajukan perubahan PO.' using errcode = '42501';
    end if;
    -- Berkas 96: sales hanya boleh mengajukan untuk PO miliknya sendiri (sama dengan cabang sp).
    -- Tanpa ini sales membaca PO sales lain lewat nilai_lama dan bisa mengunci PO itu dengan usulan palsu.
    if public.peran_saya() = 'sales'
       and not exists (select 1 from public.purchase_orders p
                        where p.id = p_ref and p.sales_rep_id = public.sales_rep_saya()) then
      raise exception 'Anda hanya bisa mengajukan perubahan untuk PO milik Anda sendiri.'
        using errcode = '42501';
    end if;
    select jsonb_build_object(
             'kepala', to_jsonb(p) - 'dibuat_pada' - 'dibuat_oleh' - 'diubah_pada' - 'diubah_oleh',
             'baris',  coalesce((select jsonb_agg(to_jsonb(l) order by l.urut)
                                   from public.po_lines l where l.po_id = p.id), '[]'::jsonb))
      into v_lama from public.purchase_orders p where p.id = p_ref;
  else
    if not public.boleh_alur_jual() then
      raise exception 'Anda tidak berwenang mengajukan perubahan SP.' using errcode = '42501';
    end if;
    -- Sales hanya boleh mengajukan untuk SP miliknya sendiri.
    if public.peran_saya() = 'sales'
       and not exists (select 1 from public.sales_orders s
                        where s.id = p_ref and s.sales_rep_id = public.sales_rep_saya()) then
      raise exception 'Anda hanya bisa mengajukan perubahan untuk SP milik Anda sendiri.'
        using errcode = '42501';
    end if;
    select jsonb_build_object(
             'kepala', to_jsonb(s) - 'dibuat_pada' - 'dibuat_oleh' - 'diubah_pada' - 'diubah_oleh',
             'baris',  coalesce((select jsonb_agg(to_jsonb(l) order by l.urut)
                                   from public.sales_order_lines l where l.so_id = s.id), '[]'::jsonb))
      into v_lama from public.sales_orders s where s.id = p_ref;
  end if;

  if v_lama is null then
    raise exception 'Dokumen yang mau diubah tidak ditemukan.';
  end if;

  -- #1/#6/#7 (berkas 94): baris PO dilengkapi dari baris tersimpan (set_id, snapshot set, diskon,
  -- diskon_tipe, keterangan) — payload yang tidak membawanya tidak lagi membuang kolom itu.
  if p_jenis = 'po' and jsonb_typeof(p_baru->'baris') = 'array' then
    p_baru := jsonb_set(p_baru, '{baris}', public.po_baris_usul_lengkap(p_ref, p_baru->'baris'));
    perform public.periksa_baris_po_usul(p_baru->'baris');
  end if;

  insert into public.usul_ubah (jenis, ref_id, nilai_lama, nilai_baru, alasan, diajukan_oleh)
  values (p_jenis, p_ref, v_lama, p_baru, btrim(p_alasan), auth.uid())
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'Sudah ada usulan perubahan yang menunggu untuk dokumen ini. '
                  'Tunggu GM memutuskannya dulu.';
end $function$;

revoke execute on function public.ajukan_ubah(text, bigint, jsonb, text) from public, anon;
grant execute on function public.ajukan_ubah(text, bigint, jsonb, text) to authenticated;

-- 2) uu_baca — usulan terbaca = dokumennya terbaca (RLS po_baca/so_baca pembaca), atau owner/GM
alter policy uu_baca on public.usul_ubah using (
  public.setara_owner()
  or (jenis = 'po' and exists (select 1 from public.purchase_orders p where p.id = usul_ubah.ref_id))
  or (jenis = 'sp' and exists (select 1 from public.sales_orders s where s.id = usul_ubah.ref_id))
);

-- Uji (DEV, transaksi rollback, 28 Sep 2026; peran staff/liesian disimulasikan dengan mengubah profil
-- nonaktif di dalam transaksi. Sesudah uji: usul_ubah 6 (2 menunggu), purchase_orders 37, po_lines 55,
-- profil nonaktif 2 — sama dengan sebelum uji):
--   Sebelum berkas ini (reproduksi temuan): Alfred (sales rep 2) select PO 60 → 0 baris, tetapi
--       ajukan_ubah('po', 60, …) LOLOS dan nilai_lama berisi PO utuh; Alfred membaca usulan #3–#8.
--   T1  Alfred ajukan_ubah PO 60 (rep 6) / PO 50 (rep 3) / PO 999999 → DITOLAK 42501 "PO milik Anda
--       sendiri"; SP 51 (rep 9) → DITOLAK (cek lama). PO 33 miliknya → LOLOS.
--   T2  Baca usul_ubah: Alfred → hanya PO 33 (miliknya); Arie (rep 3) → PO 55 (+ SP 57 miliknya yang
--       menunggu Vonny); Sarjono (rep 9) → SP 51. antrean_gm Alfred hanya PO 33; GM → semua.
--   T3  Vonny ajukan PO 60 → LOLOS (Vonny membaca semua PO); Vonny & GM membaca semua usulan.
--   T4  liesian: usulan PO & SP biasa terbaca; usulan atas SP 57 (menunggu Vonny) TIDAK terbaca —
--       sama dengan SP 57 sendiri (0 baris). staff: ajukan PO 61 → LOLOS; ajukan SP 49 (menunggu Vonny,
--       buatan Sarjono) → masih LOLOS (lihat "Tidak diubah"), tetapi usulannya tidak terbaca olehnya.
--   T5  Regresi berkas 94: Arie ajukan PO 50 miliknya format FE baru → GM putuskan_ubah → LOLOS,
--       semua kolom po_lines PO 50 sama persis dengan sebelumnya.
--   T6  has_function_privilege ajukan_ubah: anon = false, authenticated = true.
