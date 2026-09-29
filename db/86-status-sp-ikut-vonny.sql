-- Berkas 86 (#8): status SP ikut keputusan Vonny & tutup celah sales mengisi kolom cek Vonny.
--
-- Masalah (terverifikasi di DEV):
--   • Trigger so_status_dok hanya mendengar no_surat_jalan/no_invoice/no_faktur/lunas/batal/harga_ok.
--     putuskan_vonny_cek mengubah vonny_ok, tapi status TIDAK dihitung ulang → SP yang sudah
--     diloloskan tetap 'menunggu vonny', nyangkut di tab Double Check & tak pernah masuk Pengiriman.
--   • jaga_kolom_sales tidak menjaga vonny_ok/vonny_oleh/vonny_pada/vonny_alasan → sales bisa
--     PATCH vonny_ok=true pada SP-nya sendiri (atau INSERT SP dengan vonny_ok=true) dan melompati Vonny.
--   • Blok (f) jaga_kolom_sales menolak tanpa_po_* dari siapa pun selain owner/GM, termasuk lewat
--     pintu resminya tandai_sp_tanpa_po() → alur #10 "tanpa PO, cukup cek Vonny" gagal untuk
--     sales/staff/Vonny ("tidak boleh mengisi izin invoice tanpa PO").
--
-- (1) status_sp_hitung: 'menunggu vonny' hanya sebelum barang keluar (no_surat_jalan null),
--     selaras dengan jaga_gerbang_vonny & so_baca (berkas 83). Hasil untuk seluruh SP DEV = sama.
-- (2) putuskan_vonny_cek: pakai status HITUNG (kolom status bisa basi), tolak SP draft (belum ada
--     baris), tolak SP yang barangnya sudah mulai dikirim (surat jalan / so_kirim), tolak p_ok null,
--     kunci baris (for update). Status dihitung ulang oleh trigger (4), bukan di sini.
-- (3) jaga_kolom_sales:
--     e2 · kolom vonny_* hanya boleh diisi owner/GM/Vonny (boleh_konfirmasi_kirim), termasuk saat INSERT.
--     f  · tanpa_po_* tetap owner/GM, KECUALI lewat pintu resmi yang menyalakan rhj.tanpa_po
--          (tandai_sp_tanpa_po — sudah memeriksa peran & kepemilikan SP; izinkan_invoice_tanpa_po).
--     Sisa fungsi identik dengan versi live sebelum berkas ini.
-- (4) Trigger so_status_dok ikut mendengar semua kolom sales_orders yang memengaruhi status_sp_hitung:
--     vonny_ok, dan lewat so_ringkas.ada_bawah_list → pct: cash_ok, customer_id (harga_khusus),
--     sales_rep_id (komisi_flat_pct). Tak ada rekursi: UPDATE di so_sesudah_ubah hanya mengubah status.
--     ATURAN: kolom sales_orders baru yang dibaca status_sp_hitung / so_ringkas / so_baris_hitung
--     WAJIB ditambahkan ke daftar kolom trigger ini.
-- (5) Hardening: cabut EXECUTE jaga_gerbang_vonny dari public/anon (pola berkas 84).
-- (6) Data turunan: hitung ulang status SEMUA SP yang status-nya ≠ status_sp_hitung.
--     DEV: 11 SP 'menunggu vonny' → 'di gudang' (semua vonny_ok = true):
--       016, 017, 018, 019, 021, 022, 023, 024, 025, 026, 027/MCE/IX/2026 (id 44,45,47,48,50–56).
--     Nilai lama tercatat di audit_log (trigger catat_perubahan, oleh = null) sehingga bisa dipulihkan:
--       select * from audit_log where tabel='sales_orders' and aksi='UPDATE' and oleh is null
--         and sebelum->>'status' is distinct from sesudah->>'status';
--
-- Konsekuensi: dari SQL admin (tanpa JWT, peran_saya()='pending') kolom vonny_* tidak bisa diubah —
--   sama seperti kolom gerbang lain.
-- Produksi: berkas ini menuntut berkas 82 & 83 sudah terpasang. Jalankan dulu
--   select id,no_sp,status,public.status_sp_hitung(id) from sales_orders
--    where status is distinct from public.status_sp_hitung(id);
--   untuk melihat berapa SP yang akan berubah.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026. Belum ke produksi.

-- (1) ─────────────────────────────────────────────────────────────────────────
create or replace function public.status_sp_hitung(p_so bigint)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
    when s.batal                                   then 'batal'
    when s.lunas                                   then 'lunas'
    when s.no_faktur is not null                   then 'tertagih'
    when s.no_surat_jalan is not null
     and s.no_invoice is not null                  then 'terkirim'
    when coalesce(r.ada_bawah_list, false) and s.harga_ok is not true then 'menunggu gm'
    when exists (select 1 from public.sales_order_lines l where l.so_id = s.id)
     and s.vonny_ok is not true
     and s.no_surat_jalan is null                  then 'menunggu vonny'   -- #8 berkas 86: hanya sebelum barang keluar
    when exists (select 1 from public.sales_order_lines l where l.so_id = s.id)
                                                   then 'di gudang'
    else 'draft'
  end
  from public.sales_orders s
  left join public.so_ringkas r on r.so_id = s.id
  where s.id = p_so
$function$;

-- (2) ─────────────────────────────────────────────────────────────────────────
create or replace function public.putuskan_vonny_cek(p_so bigint, p_ok boolean, p_alasan text default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record; v_status text;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh memeriksa kelayakan SP.' using errcode='42501';
  end if;
  if p_ok is null then
    raise exception 'Keputusan cek Vonny wajib: loloskan atau tahan.' using errcode='22023';
  end if;
  select * into v from public.sales_orders where id = p_so for update;
  if v.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002'; end if;
  if v.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', v.no_sp using errcode='22023'; end if;
  v_status := public.status_sp_hitung(p_so);          -- #8 berkas 86: kolom status bisa basi
  if v_status = 'menunggu gm' then
    raise exception 'Surat Pesanan % masih menunggu keputusan GM. Selesaikan harga di GM dulu, baru cek Vonny.', v.no_sp using errcode='22023';
  end if;
  if v_status = 'draft' then
    raise exception 'Surat Pesanan % belum punya baris barang — belum ada yang bisa dicek.', v.no_sp using errcode='22023';
  end if;
  if v.no_surat_jalan is not null or exists (select 1 from public.so_kirim k where k.so_id = p_so) then
    raise exception 'Barang Surat Pesanan % sudah mulai dikirim — keputusan cek Vonny tidak bisa diubah lagi.', v.no_sp using errcode='22023';
  end if;
  if p_ok is false and coalesce(btrim(p_alasan),'') = '' then
    raise exception 'Menahan SP wajib beralasan supaya sales tahu apa yang perlu dibereskan.' using errcode='22023';
  end if;
  update public.sales_orders
     set vonny_ok = p_ok, vonny_oleh = auth.uid(), vonny_pada = now(),
         vonny_alasan = nullif(btrim(coalesce(p_alasan,'')),''),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_so;
  -- status dihitung ulang trigger so_status_dok (vonny_ok kini didengar, berkas 86)
  return 'Surat Pesanan ' || v.no_sp || (case when p_ok then ' dinyatakan layak diproses.' else ' DITAHAN Vonny.' end);
end $function$;

-- (3) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_kolom_sales()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  ins    boolean := (tg_op = 'INSERT');
  v_kol  text;
  v_siapa text;
  -- berubah(kolom): pada INSERT = "diisi padahal SP baru", pada UPDATE =
  -- "nilainya bergeser". Ditulis sebagai dua ekspresi kecil di tiap baris
  -- di bawah supaya bisa dibaca berpasangan dengan kolomnya.
begin
  -- Kolom yang diisi trigger sistem (status, telat, diubah_*) tidak lewat
  -- sini sama sekali — masing-masing punya penjaganya sendiri.

  -- a · dokumen terbit: Lie Sian, GM, owner
  if not public.boleh_terbitkan() then
    v_kol := case
      when (case when ins then new.no_surat_jalan  is not null else new.no_surat_jalan  is distinct from old.no_surat_jalan  end) then 'Nomor Surat Jalan'
      when (case when ins then new.tgl_surat_jalan is not null else new.tgl_surat_jalan is distinct from old.tgl_surat_jalan end) then 'Tanggal Surat Jalan'
      when (case when ins then new.no_invoice      is not null else new.no_invoice      is distinct from old.no_invoice      end) then 'Nomor Invoice'
      when (case when ins then new.tgl_invoice     is not null else new.tgl_invoice     is distinct from old.tgl_invoice     end) then 'Tanggal Invoice'
      when (case when ins then new.no_faktur       is not null else new.no_faktur       is distinct from old.no_faktur       end) then 'Nomor Faktur Pajak'
      when (case when ins then new.tgl_faktur      is not null else new.tgl_faktur      is distinct from old.tgl_faktur      end) then 'Tanggal Faktur Pajak'
      else null end;
    v_siapa := 'Lie Sian, GM, atau owner';
  end if;

  -- b · pelunasan: Ichi, GM, owner
  if v_kol is null and not public.boleh_pelunasan() then
    v_kol := case
      when (case when ins then new.lunas     is true    else new.lunas     is distinct from old.lunas     end) then 'status Lunas'
      when (case when ins then new.tgl_lunas is not null else new.tgl_lunas is distinct from old.tgl_lunas end) then 'Tanggal Lunas'
      else null end;
    v_siapa := 'Ichi, GM, atau owner';
  end if;

  -- c · pencocokan cash: finance, Ichi, GM, owner (sama seperti cocokkan_cash_sp)
  if v_kol is null and public.peran_saya() not in ('owner','gm','finance','ichi') then
    v_kol := case
      when (case when ins then new.cash_ok   is not null else new.cash_ok   is distinct from old.cash_ok   end) then 'konfirmasi Cash'
      when (case when ins then new.cash_oleh is not null else new.cash_oleh is distinct from old.cash_oleh end) then 'pencatat konfirmasi Cash'
      when (case when ins then new.cash_pada is not null else new.cash_pada is distinct from old.cash_pada end) then 'waktu konfirmasi Cash'
      else null end;
    v_siapa := 'finance, Ichi, GM, atau owner';
  end if;

  -- d · keputusan GM: harga, komisi, klaim dini
  if v_kol is null and not public.boleh_approve() then
    v_kol := case
      when (case when ins then new.harga_ok    is not null else new.harga_ok    is distinct from old.harga_ok    end) then 'persetujuan harga GM'
      when (case when ins then new.gm_pct      is not null else new.gm_pct      is distinct from old.gm_pct      end) then 'persentase komisi GM'
      when (case when ins then new.gm_oleh     is not null else new.gm_oleh     is distinct from old.gm_oleh     end) then 'pemberi persetujuan GM'
      when (case when ins then new.gm_pada     is not null else new.gm_pada     is distinct from old.gm_pada     end) then 'waktu persetujuan GM'
      when (case when ins then new.ehc_dini_ok is true    else new.ehc_dini_ok is distinct from old.ehc_dini_ok end) then 'persetujuan klaim dini'
      else null end;
    v_siapa := 'GM atau owner';
  end if;

  -- e · izin kirim: Vonny, GM, owner
  if v_kol is null and not public.boleh_konfirmasi_kirim() then
    v_kol := case
      when (case when ins then new.kirim_ok      is not null else new.kirim_ok      is distinct from old.kirim_ok      end) then 'izin pengiriman'
      when (case when ins then new.kirim_ok_oleh is not null else new.kirim_ok_oleh is distinct from old.kirim_ok_oleh end) then 'pemberi izin pengiriman'
      when (case when ins then new.kirim_ok_pada is not null else new.kirim_ok_pada is distinct from old.kirim_ok_pada end) then 'waktu izin pengiriman'
      when (case when ins then new.kirim_alasan  is not null else new.kirim_alasan  is distinct from old.kirim_alasan  end) then 'alasan keputusan pengiriman'
      else null end;
    v_siapa := 'Vonny, GM, atau owner';
  end if;

  -- e2 · cek kelayakan Vonny (#8, berkas 86): Vonny, GM, owner — lewat putuskan_vonny_cek.
  --      Sales tidak boleh meloloskan SP-nya sendiri, termasuk saat INSERT.
  if v_kol is null and not public.boleh_konfirmasi_kirim() then
    v_kol := case
      when (case when ins then new.vonny_ok     is not null else new.vonny_ok     is distinct from old.vonny_ok     end) then 'keputusan cek Vonny'
      when (case when ins then new.vonny_oleh   is not null else new.vonny_oleh   is distinct from old.vonny_oleh   end) then 'pemeriksa cek Vonny'
      when (case when ins then new.vonny_pada   is not null else new.vonny_pada   is distinct from old.vonny_pada   end) then 'waktu cek Vonny'
      when (case when ins then new.vonny_alasan is not null else new.vonny_alasan is distinct from old.vonny_alasan end) then 'alasan cek Vonny'
      else null end;
    v_siapa := 'Vonny, GM, atau owner';
  end if;

  -- f · pengecualian invoice tanpa PO: GM, owner — atau lewat pintu resminya
  --     (tandai_sp_tanpa_po / izinkan_invoice_tanpa_po) yang menyalakan rhj.tanpa_po
  --     dan sudah memeriksa peran & kepemilikan SP (#10, berkas 86).
  if v_kol is null and not public.setara_owner()
     and coalesce(current_setting('rhj.tanpa_po', true), '') <> '1' then
    v_kol := case
      when (case when ins then new.tanpa_po_ok     is true    else new.tanpa_po_ok     is distinct from old.tanpa_po_ok     end) then 'izin invoice tanpa PO'
      when (case when ins then new.tanpa_po_alasan is not null else new.tanpa_po_alasan is distinct from old.tanpa_po_alasan end) then 'alasan invoice tanpa PO'
      when (case when ins then new.tanpa_po_oleh   is not null else new.tanpa_po_oleh   is distinct from old.tanpa_po_oleh   end) then 'pemberi izin invoice tanpa PO'
      when (case when ins then new.tanpa_po_pada   is not null else new.tanpa_po_pada   is distinct from old.tanpa_po_pada   end) then 'waktu izin invoice tanpa PO'
      else null end;
    v_siapa := 'GM atau owner';
  end if;

  -- g · pemilik SP. Hanya pada UPDATE — pada INSERT, jaga_pemilik_dokumen()
  --     yang menanganinya (sales otomatis jadi pemilik, tidak bisa menunjuk
  --     orang lain). Dua penjaga untuk satu kolom akan saling menabrak.
  if v_kol is null and not ins and not public.boleh_ubah_impor() then
    if new.sales_rep_id is distinct from old.sales_rep_id then
      v_kol := 'sales pemilik SP'; v_siapa := 'staff, GM, atau owner';
    end if;
  end if;

  -- h · pembatalan: siapa pun yang memegang alur jual, TERMASUK sales untuk
  --     SP-nya sendiri (RLS yang membatasi "miliknya sendiri").
  if v_kol is null and not public.boleh_alur_jual() then
    v_kol := case
      when (case when ins then new.batal        is true    else new.batal        is distinct from old.batal        end) then 'pembatalan SP'
      when (case when ins then new.alasan_batal is not null else new.alasan_batal is distinct from old.alasan_batal end) then 'alasan pembatalan'
      else null end;
    v_siapa := 'sales pemilik, staff, GM, atau owner';
  end if;

  if v_kol is not null then
    raise exception
      'Peran Anda (%) tidak boleh mengisi % pada Surat Pesanan %. Kolom itu wewenang %. '
      'Layar ini terbuka supaya Anda bisa MEMANTAU, bukan mengisi.',
      public.peran_saya(), v_kol, coalesce(new.no_sp, '(baru)'), v_siapa
      using errcode = '42501';
  end if;
  return new;
end $function$;

-- (4) ─────────────────────────────────────────────────────────────────────────
create or replace trigger so_status_dok
  after insert or update of no_surat_jalan, no_invoice, no_faktur, lunas, batal, harga_ok,
                            vonny_ok, cash_ok, customer_id, sales_rep_id
  on public.sales_orders
  for each row execute function public.so_sesudah_ubah();

-- (5) ─────────────────────────────────────────────────────────────────────────
revoke execute on function public.jaga_gerbang_vonny() from public, anon;

-- (6) ─────────────────────────────────────────────────────────────────────────
do $$
begin
  perform set_config('rhj.hitung_status', 'on', true);
  update public.sales_orders s set status = public.status_sp_hitung(s.id)
   where s.status is distinct from public.status_sp_hitung(s.id);
  perform set_config('rhj.hitung_status', 'off', true);
end $$;
