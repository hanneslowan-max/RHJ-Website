-- Berkas 99 (#18, lanjutan berkas 97/98): finalisasi surat jalan oleh sistem tidak tersandung
--   penjaga kolom per peran.
--
-- Temuan saat uji berkas 98 (DEV, begin…rollback): Vonny/sales membatalkan sisa qty terakhir → semua
--   sisa 0 → finalisasi_kirim_sp mengisi no_surat_jalan (batch terakhir). jaga_kolom_sales (a) menolak
--   karena peran pemanggil bukan boleh_terbitkan() ("Peran Anda (vonny) tidak boleh mengisi Nomor Surat
--   Jalan…") — DEADLOCK (e) pindah tempat.
-- Perbaikan:
--   (1) jaga_kolom_sales (a): kolom no_surat_jalan/tgl_surat_jalan dilewati selama flag sistem
--       rhj.sj_final = '1'. Flag itu hanya dinyalakan finalisasi_kirim_sp, yang mengisi nomor/tanggal
--       dari surat jalan bertahap yang SUDAH diterbitkan Lie Sian/GM/owner (bukan nilai ketikan pemanggil).
--       Invoice/faktur tetap wewenang Lie Sian/GM/owner. Sisa fungsi identik dengan versi live.
--   (2) finalisasi_kirim_sp menyalakan rhj.sj_final bersama rhj.kirim.
-- Data: tidak ada yang diubah.

-- (1) ─────────────────────────────────────────────────────────────────────────
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
  -- #18 berkas 99: finalisasi surat jalan bertahap oleh sistem (finalisasi_kirim_sp)
  v_sj_final boolean := coalesce(current_setting('rhj.sj_final', true), '') = '1';
  -- berubah(kolom): pada INSERT = "diisi padahal SP baru", pada UPDATE =
  -- "nilainya bergeser". Ditulis sebagai dua ekspresi kecil di tiap baris
  -- di bawah supaya bisa dibaca berpasangan dengan kolomnya.
begin
  -- Kolom yang diisi trigger sistem (status, telat, diubah_*) tidak lewat
  -- sini sama sekali — masing-masing punya penjaganya sendiri.

  -- a · dokumen terbit: Lie Sian, GM, owner
  if not public.boleh_terbitkan() then
    v_kol := case
      when not v_sj_final and (case when ins then new.no_surat_jalan  is not null else new.no_surat_jalan  is distinct from old.no_surat_jalan  end) then 'Nomor Surat Jalan'
      when not v_sj_final and (case when ins then new.tgl_surat_jalan is not null else new.tgl_surat_jalan is distinct from old.tgl_surat_jalan end) then 'Tanggal Surat Jalan'
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
  --      Pengecualian (berkas 88): sistem MENGGUGURKAN keputusan lolos lewat gugurkan_cek_vonny()
  --      (flag rhj.vonny_gugur) — hanya mengosongkan vonny_ok/oleh/pada, tidak bisa meloloskan.
  if v_kol is null and not public.boleh_konfirmasi_kirim()
     and not (not ins
              and coalesce(current_setting('rhj.vonny_gugur', true), '') = '1'
              and new.vonny_ok is null and new.vonny_oleh is null and new.vonny_pada is null
              and new.vonny_alasan is not distinct from old.vonny_alasan) then
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
  --     dan sudah memeriksa peran, pembuat & tahap SP (#10 berkas 86, #8 berkas 88).
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

-- (2) ─────────────────────────────────────────────────────────────────────────
create or replace function public.finalisasi_kirim_sp(p_so bigint)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s record; k record; v_lengkap boolean;
begin
  select * into s from public.sales_orders where id = p_so;
  if s.id is null or s.batal then return null; end if;
  -- jalur "kirim sekaligus" / belum ada surat jalan bertahap: tidak disentuh
  if not exists (select 1 from public.so_kirim where so_id = p_so) then return null; end if;
  select coalesce(bool_and(z.sisa <= 0), true) into v_lengkap from public.so_kirim_sisa z where z.so_id = p_so;
  if v_lengkap and s.no_surat_jalan is null then
    select kk.no_surat_jalan, kk.tgl into k from public.so_kirim kk where kk.so_id = p_so order by kk.id desc limit 1;
    perform set_config('rhj.kirim','1',true);
    perform set_config('rhj.sj_final','1',true);   -- berkas 99: nomor dari surat jalan yang sudah terbit
    -- gerbang jaga_urutan_dokumen_sp & jaga_gerbang_vonny tetap berlaku di UPDATE ini
    update public.sales_orders set no_surat_jalan = k.no_surat_jalan, tgl_surat_jalan = k.tgl where id = p_so;
    perform set_config('rhj.sj_final','',true);
    perform set_config('rhj.kirim','',true);
    return 'lengkap';
  elsif not v_lengkap and s.no_surat_jalan is not null then
    if s.no_invoice is not null then
      raise exception 'Invoice Surat Pesanan % sudah terbit — pengiriman tidak bisa dibuka lagi.', s.no_sp
        using errcode='23514'; end if;
    perform set_config('rhj.kirim','1',true);
    perform set_config('rhj.sj_final','1',true);
    update public.sales_orders set no_surat_jalan = null, tgl_surat_jalan = null where id = p_so;
    perform set_config('rhj.sj_final','',true);
    perform set_config('rhj.kirim','',true);
    return 'dibuka';
  end if;
  return case when v_lengkap then 'lengkap' else 'sisa' end;
end $function$;

revoke all on function public.finalisasi_kirim_sp(bigint) from public, anon, authenticated;  -- internal
revoke execute on function public.jaga_kolom_sales() from public, anon;

notify pgrst, 'reload schema';
