-- Berkas 88 (#8, perbaikan temuan review berkas 86): cek Vonny tidak bisa dilangkahi lagi.
--
-- Temuan (semua diverifikasi ulang di DEV dengan begin…rollback sebelum berkas ini):
--   A (blocker) tandai_sp_tanpa_po() bisa dipakai sales (SP miliknya) & staff/vonny (SP mana pun)
--     KAPAN SAJA — sesudah Vonny meloloskan, bahkan sesudah surat jalan. SP "PO menyusul" yang
--     invoicenya ditahan jadi bisa dilepas sendiri oleh sales (gerbang 3b jaga_urutan_dokumen_sp
--     dilangkahi). Uji: SP 44 → Liesian isi surat jalan → sales Riksa tandai tanpa PO → Liesian
--     isi invoice: LOLOS, status 'terkirim' tanpa PO.
--   B (major) keputusan Vonny tidak gugur saat isi SP berubah: sales bisa menambah baris
--     (INSERT sales_order_lines tidak dijaga sama sekali — trigger sol_jaga_usul hanya
--     BEFORE UPDATE/DELETE) dan mengganti customer_id SP-nya yang sudah vonny_ok=true; SP tetap
--     'di gudang' & langsung terbuka untuk Liesian. Uji: SP 44 +baris qty 100, SP 45 customer
--     1729→1 → vonny_ok tetap true.
--   C (major) staff tidak bisa membuat SP: so_baca (berkas 83) menyembunyikan SP yang belum lolos
--     Vonny dari staff, sehingga INSERT … RETURNING (simpanSp, return=representation) ditolak
--     42501 dan INSERT baris ditolak sol_tulis (EXISTS pada SP yang tak terlihat).
--
-- Perbaikan:
--   (1) tandai_sp_tanpa_po: pintu untuk PEMBUAT SP saat menyimpan (desain berkas 72), bukan
--       pelepas invoice. Selain owner/GM: wajib pembuat SP (dibuat_oleh = dirinya; sales juga
--       wajib pemilik), SP belum diputus Vonny (vonny_ok null), belum ada surat jalan / so_kirim /
--       invoice. SP batal ditolak untuk semua. Owner/GM tetap bebas (setara izinkan_invoice_tanpa_po).
--   (2) jaga_kolom_sales e2: sistem boleh MENGGUGURKAN keputusan lolos Vonny (vonny_ok/oleh/pada →
--       null) lewat gugurkan_cek_vonny() yang menyalakan rhj.vonny_gugur. Hanya mengosongkan —
--       tidak bisa meloloskan. Sisa fungsi identik dengan berkas 86.
--   (3) gugurkan_cek_vonny(p_so): kosongkan vonny_ok/oleh/pada bila vonny_ok = true, SP tidak batal,
--       dan barang belum keluar (no_surat_jalan null, tak ada so_kirim). UPDATE-nya menyebut
--       vonny_ok → trigger so_status_dok menghitung ulang status → 'menunggu vonny' (SP pindah
--       lagi dari Pengiriman ke tab Double Check). Hanya dipanggil trigger; EXECUTE dicabut dari
--       public/anon/authenticated.
--   (4) Trigger sol_vonny_gugur (AFTER INSERT/UPDATE/DELETE baris SP): perubahan baris yang dilihat
--       Vonny (produk, qty, harga nett, EHC, jenis, deskripsi, batal/pulihkan) oleh peran selain
--       owner/GM/Vonny → gugurkan_cek_vonny. Termasuk batalkan_baris_sp/pulihkan_baris_sp oleh sales.
--   (5) Trigger so_vonny_gugur (AFTER UPDATE sales_orders, WHEN kolom kepala berubah): customer_id,
--       kepada, alamat, up, telp, ppn_kena, catatan, PO dilepas/diganti (po_id lama tidak null),
--       atau mode "PO menyusul"/alasannya berganti pada SP tanpa PO — oleh peran selain
--       owner/GM/Vonny → gugurkan_cek_vonny. Menempelkan PO ke SP tanpa PO
--       (po_id null → isi) TIDAK menggugurkan — itu menguatkan; tapi bila tautkan_po_sp sekaligus
--       mengisi customer_id yang tadinya kosong, pelanggannya berubah → gugur (Vonny cek ulang).
--       AFTER (bukan BEFORE) supaya RETURNING milik UPDATE asal masih lolos so_baca.
--   (6) Trigger sol_jaga_tambah (BEFORE INSERT baris SP): selain owner/GM (atau jalur usul GM,
--       rhj.usul), baris baru hanya boleh ditambahkan selama SP masih segar — belum batal, belum
--       diputus Vonny (vonny_ok null) maupun GM (harga_ok null), belum ada surat jalan / so_kirim /
--       invoice. Satu-satunya jalur layar yang menambah baris oleh non-GM adalah simpanSp (SP baru,
--       semua kolom itu masih null). Sesudahnya: "Minta ubah SP" → GM. Sekaligus menutup celah
--       "tambah baris di bawah price list sesudah GM menyetujui harga".
--   (7) so_baca: pembuat SP yang masih memegang alur jual (owner/gm/staff/sales) tetap melihat SP
--       buatannya selama menunggu Vonny → staff bisa membuat SP lagi (INSERT … RETURNING & baris).
--       Peran lain tetap tidak melihat SP yang sedang dicek Vonny (maksud berkas 83 tetap).
--   (8) Hardening: cabut EXECUTE fungsi trigger baru dari public/anon (pola berkas 84).
--
-- Konsekuensi: perubahan lewat SQL admin (tanpa JWT, peran_saya()='pending') pada SP yang sudah
--   lolos juga menggugurkan cek Vonny — sama seperti peran non-pemeriksa lain.
-- Data: tidak ada data yang diubah berkas ini (status semua SP DEV sudah = status_sp_hitung).
-- Produksi: menuntut berkas 82, 83, 86 sudah terpasang.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026. Belum ke produksi.

-- (1) ─────────────────────────────────────────────────────────────────────────
create or replace function public.tandai_sp_tanpa_po(p_so bigint, p_alasan text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record;
begin
  if not public.boleh_input_po() then
    raise exception 'Anda tidak berhak membuat Surat Pesanan.' using errcode='42501';
  end if;
  if coalesce(btrim(p_alasan),'') = '' then
    raise exception 'Mode tanpa PO wajib beralasan (mis. pelanggan tidak menerbitkan PO / order lisan).'
      using errcode='22023';
  end if;
  select * into v from public.sales_orders where id = p_so for update;
  if v.id is null then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002';
  end if;
  if v.batal then
    raise exception 'Surat Pesanan % sudah dibatalkan.', v.no_sp using errcode='22023';
  end if;
  if v.po_id is not null then
    raise exception 'Surat Pesanan % sudah punya PO — tidak perlu mode tanpa PO.', v.no_sp
      using errcode='22023';
  end if;
  -- #8 berkas 88: selain owner/GM, pintu ini hanya untuk PEMBUAT SP saat menyimpannya —
  -- sebelum SP dicek Vonny dan sebelum barang keluar. Melepas invoice SP "PO menyusul"
  -- sesudah itu tetap wewenang owner/GM (izinkan_invoice_tanpa_po).
  if not public.setara_owner() then
    if v.dibuat_oleh is distinct from auth.uid()
       or (public.peran_saya() = 'sales' and v.sales_rep_id is distinct from public.sales_rep_saya()) then
      raise exception 'Mode tanpa PO Surat Pesanan % hanya bisa dinyatakan oleh pembuatnya saat menyimpan SP. '
                      'Minta owner/GM kalau perlu diubah.', v.no_sp
        using errcode='42501';
    end if;
    if v.no_surat_jalan is not null or v.no_invoice is not null
       or exists (select 1 from public.so_kirim k where k.so_id = p_so) then
      raise exception 'Barang Surat Pesanan % sudah mulai dikirim — mode tanpa PO tidak bisa dinyatakan lagi. '
                      'Minta owner/GM (tombol "Izinkan tanpa PO").', v.no_sp
        using errcode='42501';
    end if;
    if v.vonny_ok is not null then
      raise exception 'Surat Pesanan % sudah diputus Vonny (%). Mode tanpa PO hanya bisa dinyatakan sebelum '
                      'SP dicek Vonny — sesudahnya minta owner/GM (tombol "Izinkan tanpa PO").',
                      v.no_sp, case when v.vonny_ok then 'diloloskan' else 'ditahan' end
        using errcode='42501';
    end if;
  end if;

  perform set_config('rhj.tanpa_po','1',true);
  update public.sales_orders
     set tanpa_po_ok    = true,
         tanpa_po_alasan= btrim(p_alasan),
         tanpa_po_oleh  = coalesce(tanpa_po_oleh, auth.uid()),
         tanpa_po_pada  = coalesce(tanpa_po_pada, now()),
         po_menyusul    = false,
         po_menyusul_alasan = null
   where id = p_so;
  perform set_config('rhj.tanpa_po','',true);

  return 'Surat Pesanan ' || v.no_sp || ' ditandai TANPA PO. Cek Vonny tetap wajib sebelum surat jalan.';
end $function$;

-- (2) ─────────────────────────────────────────────────────────────────────────
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

-- (3) ─────────────────────────────────────────────────────────────────────────
create or replace function public.gugurkan_cek_vonny(p_so bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_so is null then return; end if;
  perform set_config('rhj.vonny_gugur', '1', true);
  -- Menyebut vonny_ok → so_status_dok menghitung ulang status ('menunggu vonny').
  update public.sales_orders s
     set vonny_ok = null, vonny_oleh = null, vonny_pada = null
   where s.id = p_so
     and s.vonny_ok is true
     and not s.batal
     and s.no_surat_jalan is null
     and not exists (select 1 from public.so_kirim k where k.so_id = s.id);
  perform set_config('rhj.vonny_gugur', '', true);
end $function$;

revoke execute on function public.gugurkan_cek_vonny(bigint) from public, anon, authenticated;

-- (4) ─────────────────────────────────────────────────────────────────────────
create or replace function public.sp_vonny_gugur_baris()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  -- Pemeriksa (Vonny) & owner/GM tidak menggugurkan: perubahan mereka sudah dilihat pemeriksa.
  if public.boleh_konfirmasi_kirim() then return null; end if;
  if tg_op = 'UPDATE'
     and new.so_id is not distinct from old.so_id
     and (new.product_id, new.qty, new.harga_nett, new.ehc_item, new.jenis, new.deskripsi, new.batal)
         is not distinct from
         (old.product_id, old.qty, old.harga_nett, old.ehc_item, old.jenis, old.deskripsi, old.batal) then
    return null;   -- kolom yang tidak dilihat Vonny (mis. urut, harga_list)
  end if;
  if tg_op <> 'DELETE' then perform public.gugurkan_cek_vonny(new.so_id); end if;
  if tg_op <> 'INSERT' and (tg_op = 'DELETE' or new.so_id is distinct from old.so_id) then
    perform public.gugurkan_cek_vonny(old.so_id);
  end if;
  return null;
end $function$;

drop trigger if exists sol_vonny_gugur on public.sales_order_lines;
create trigger sol_vonny_gugur
  after insert or update or delete on public.sales_order_lines
  for each row execute function public.sp_vonny_gugur_baris();

-- (5) ─────────────────────────────────────────────────────────────────────────
create or replace function public.sp_vonny_gugur_kepala()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if public.boleh_konfirmasi_kirim() then return null; end if;
  perform public.gugurkan_cek_vonny(new.id);
  return null;
end $function$;

drop trigger if exists so_vonny_gugur on public.sales_orders;
create trigger so_vonny_gugur
  after update on public.sales_orders
  for each row
  when (   old.customer_id is distinct from new.customer_id
        or old.kepada      is distinct from new.kepada
        or old.alamat      is distinct from new.alamat
        or old.up          is distinct from new.up
        or old.telp        is distinct from new.telp
        or old.ppn_kena    is distinct from new.ppn_kena
        or old.catatan     is distinct from new.catatan
        or (old.po_id is not null and old.po_id is distinct from new.po_id)
        or (new.po_id is null
            and (   old.po_menyusul        is distinct from new.po_menyusul
                 or old.po_menyusul_alasan is distinct from new.po_menyusul_alasan)))
  execute function public.sp_vonny_gugur_kepala();

-- (6) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_tambah_baris_sp()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s record;
begin
  if public.boleh_ubah_langsung() then return new; end if;                           -- owner/GM
  if coalesce(current_setting('rhj.usul', true), '') = 'on' then return new; end if;  -- usul yang diputus GM
  select * into s from public.sales_orders where id = new.so_id;
  if s.id is null then return new; end if;   -- FK yang menolak
  if s.batal or s.no_surat_jalan is not null or s.no_invoice is not null
     or s.vonny_ok is not null or s.harga_ok is not null
     or exists (select 1 from public.so_kirim k where k.so_id = s.id) then
    raise exception
      'Surat Pesanan % sudah diperiksa atau diproses — baris baru tidak bisa ditambahkan langsung. '
      'Ajukan lewat "Minta ubah SP"; GM yang memutuskan, lalu SP dicek ulang bila perlu.', s.no_sp
      using errcode = '42501';
  end if;
  return new;
end $function$;

drop trigger if exists sol_jaga_tambah on public.sales_order_lines;
create trigger sol_jaga_tambah
  before insert on public.sales_order_lines
  for each row execute function public.jaga_tambah_baris_sp();

-- (7) ─────────────────────────────────────────────────────────────────────────
alter policy so_baca on public.sales_orders using (
  ( public.peran_saya() = 'sales' and sales_rep_id = public.sales_rep_saya() )
  or case
       when (not batal and no_surat_jalan is null and coalesce(vonny_ok, false) = false)
         then public.peran_saya() in ('owner','gm','vonny')
              or (dibuat_oleh = auth.uid() and public.boleh_alur_jual())   -- berkas 88: pembuat SP
         else public.boleh_lihat_semua_jual()
     end
);

-- (8) ─────────────────────────────────────────────────────────────────────────
revoke execute on function public.sp_vonny_gugur_baris()  from public, anon;
revoke execute on function public.sp_vonny_gugur_kepala() from public, anon;
revoke execute on function public.jaga_tambah_baris_sp()  from public, anon;
