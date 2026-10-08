-- ═══════════════════════════════════════════════════════════════════════
-- 133 · Temuan keamanan #9: tanggal & nomor Surat Pesanan diisi sistem dan dijaga
--
-- Celah: sales_orders.tanggal bisa dikirim/diubah sales lewat REST (POST/PATCH/upsert, juga SP yang sudah lunas) —
-- tidak ada di jaga_kolom_sales, RLS so_tambah/so_ubah hanya memeriksa pemilik/pelanggan. Price list baris dibekukan
-- "berlaku pada tanggal SP" (berkas 130: beku_harga_list_baris → harga_list_pada(product, tanggal, dibuat_pada)), jadi
-- tanggal mundur ke masa price list lebih rendah membuat harga jual tidak lagi di bawah list → tier naik, perlu_gm
-- false, gerbang GM (status 'menunggu gm', surat jalan, klaim komisi) terlewati. Uji DEV: TFH Rubber 8" @300.000 —
-- tanggal 12 Agu: list 298.000, tier 2%, 'menunggu vonny'; hari ini: list 517.600, 'menunggu gm'. Jalur kedua: PATCH
-- tanggal mundur lalu "Minta ubah SP" menambah produk → baris baru dibekukan pada tanggal mundur. Tanggal SP juga
-- dipakai laporan penjualan/margin, HPP di laci GM, umur SP menunggu PO, penjualan grup tahun ini.
-- Nomor SP: nomor_sp_baru(p_tanggal) menerima tanggal bebas dan no_sp adalah teks bebas — sales bisa memakai nomor
-- bulan lain / menghabiskan counter bulan lain, dan mengubah nomor sesudah SP dibuat.
--
-- Perbaikan (semua peran yang bersesi selain owner/GM; impor/migrasi tanpa sesi apa adanya):
--  (1) SP baru: tanggal := hari ini menurut jam server (UTC) — tanggal kiriman layar/REST diabaikan, tidak ditolak.
--      Zona waktu sesi (header REST "Prefer: timezone=…") tidak berpengaruh: tanggal dihitung dari now() at time zone
--      'UTC', bukan current_date. Tetap UTC seperti selama ini (layar: toISOString; nomor_sp_baru: current_date di sesi
--      UTC) — SP pukul 00.00–06.59 WIB bertanggal kemarin, sama dengan nomornya.
--  (2) SP baru: nomor wajib "NNN/MCE/<bulan romawi>/<tahun>" untuk bulan/tahun tanggal itu, angka dalam bentuk baku
--      (minimal 3 digit, tanpa nol tambahan) dan sudah pernah dikeluarkan counter bulan itu (≤ sp_counter.terakhir).
--      Alur layar (nomor_sp_baru() lalu POST) selalu lolos; hanya bila nomor diambil di detik terakhir bulan UTC dan
--      SP tersimpan sesudah pergantian bulan, SP ditolak — simpan ulang mengambil nomor baru.
--  (3) Sesudah dibuat: tanggal dan nomor SP hanya bisa diubah owner/GM (sama dengan jaga_pembuat_sp untuk
--      dibuat_oleh/dibuat_pada). PATCH yang mengirim nilai sama tetap lolos. Mengubah tanggal TIDAK menghitung ulang
--      price list baris yang sudah beku (berkas 130).
--  (4) nomor_sp_baru: p_tanggal hanya dipakai owner/GM; peran lain selalu mendapat nomor bulan hari ini (UTC).
--
-- Tidak diubah: jaga_kolom_sales, isi_dibuat_pada_sp, putuskan_ubah (tidak menulis tanggal/nomor SP), objek EHC/komisi,
-- tanggal PO (tanggal dokumen PO customer — sah mundur, tidak dipakai price list/komisi/gerbang; sesudah dibuat hanya
-- owner/GM atau lewat usulan). Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- Sebelum rilis PROD: jalankan pemeriksaan baca-saja di HANDOFF (SP yang tanggalnya ≠ tanggal baris audit INSERT-nya).
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.jaga_tanggal_sp()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_hari date := (now() at time zone 'UTC')::date;   -- jam server; tidak ikut TimeZone sesi
  v_angka text;
  v_maks integer;
  v_salah boolean := false;
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;   -- impor tanpa sesi; owner/GM

  if tg_op = 'INSERT' then
    new.tanggal := v_hari;                                                  -- (1) diisi sistem
    -- (2) nomor bulan itu, bentuk baku, sudah dikeluarkan counter
    v_angka := split_part(coalesce(new.no_sp, ''), '/', 1);
    if v_angka !~ '^[0-9]{3,6}$' then
      v_salah := true;
    elsif v_angka <> lpad(v_angka::int::text, 3, '0')
       or new.no_sp <> v_angka || '/MCE/' || public.bulan_romawi(extract(month from v_hari)::int)
                       || '/' || extract(year from v_hari)::int then
      v_salah := true;
    else
      select c.terakhir into v_maks from public.sp_counter c
       where c.tahun = extract(year from v_hari)::int and c.bulan = extract(month from v_hari)::int;
      v_salah := v_angka::int < 1 or v_angka::int > coalesce(v_maks, 0);
    end if;
    if v_salah then
      raise exception
        'Nomor Surat Pesanan % tidak sesuai — nomor diambil sistem untuk bulan SP dibuat (%). '
        'Simpan ulang SP-nya; bila tetap ditolak, muat ulang halaman.',
        coalesce(new.no_sp, '(kosong)'), to_char(v_hari, 'MM-YYYY')
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- (3) sesudah dibuat
  if new.tanggal is distinct from old.tanggal then
    raise exception
      'Tanggal Surat Pesanan % dicatat sistem saat SP dibuat (%) dan tidak bisa diubah — tanggal itu yang '
      'menentukan price list, komisi, dan gerbang GM SP ini. Bila memang keliru, minta GM atau owner membetulkannya.',
      coalesce(old.no_sp, '(baru)'), to_char(old.tanggal, 'DD-MM-YYYY')
      using errcode = '42501';
  end if;
  if new.no_sp is distinct from old.no_sp then
    raise exception
      'Nomor Surat Pesanan % diberikan sistem saat SP dibuat dan tidak bisa diubah. Bila memang keliru, minta GM '
      'atau owner membetulkannya.', old.no_sp
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_tanggal_sp() from public, anon, authenticated;

-- nama so_a_tanggal_kini: menyala sesudah so_a_dibuat_kini & so_a_mode_ppn, sebelum so_audit_ins dan penjaga lain;
-- tidak ada BEFORE trigger lain yang membaca tanggal/no_sp. Baris SP disisipkan sesudah kepala, sehingga
-- beku_harga_list_baris membaca tanggal yang sudah dipaksa.
create or replace trigger so_a_tanggal_kini
  before insert or update of tanggal, no_sp on public.sales_orders
  for each row execute function public.jaga_tanggal_sp();

-- (4) p_tanggal hanya untuk owner/GM (layar memanggil tanpa argumen)
create or replace function public.nomor_sp_baru(p_tanggal date default current_date)
returns text language plpgsql security definer set search_path = public as $$
declare v_no integer; v_th integer; v_bl integer;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengambil nomor Surat Pesanan.' using errcode = '42501';
  end if;
  if not public.setara_owner() or p_tanggal is null then
    p_tanggal := (now() at time zone 'UTC')::date;   -- 133: sama dengan tanggal yang dipaksa saat SP disimpan
  end if;
  v_th := extract(year from p_tanggal)::int;
  v_bl := extract(month from p_tanggal)::int;
  insert into public.sp_counter (tahun, bulan, terakhir) values (v_th, v_bl, 1)
    on conflict (tahun, bulan) do update set terakhir = public.sp_counter.terakhir + 1
    returning terakhir into v_no;
  return lpad(v_no::text, 3, '0') || '/MCE/' || public.bulan_romawi(v_bl)
         || '/' || v_th::text;
end $$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass
                  and tgname = 'so_a_tanggal_kini' and tgenabled = 'O') then
    raise exception '133: trigger so_a_tanggal_kini tidak terpasang';
  end if;
end $$;
