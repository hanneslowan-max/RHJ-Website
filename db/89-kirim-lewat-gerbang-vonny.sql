-- Berkas 89 (#8, perbaikan temuan review lensa keamanan-data atas berkas 86/88):
--   pengiriman bertahap tidak bisa melangkahi cek Vonny lagi.
--
-- Temuan yang diperiksa ulang di DEV (begin…rollback) sebelum berkas ini:
--   T1 (major) tandai_sp_tanpa_po membuka pintu untuk SP yang barangnya sudah keluar.
--      → SUDAH DITUTUP berkas 88 (selain owner/GM: hanya pembuat SP, sebelum cek Vonny, sebelum
--        surat jalan/so_kirim/invoice). Uji ulang: sales Riksa pada SP 44 (sudah lolos Vonny) DITOLAK;
--        sesudah owner mengisi SJ, sales Riksa & staff DITOLAK; invoice tetap DITOLAK gerbang 3b.
--        Tidak ada perubahan untuk T1 di berkas ini.
--   T2 (major) gerbang Vonny bisa dilewati lewat tabel so_kirim / so_kirim_baris.
--      → BENAR. Tak ada trigger di kedua tabel dan RLS tulisnya hanya boleh_terbitkan().
--        Uji: Liesian (profil 8e35… diberi peran liesian sementara) tidak melihat SP 57
--        ('menunggu vonny'), tetapi INSERT so_kirim(so_id=57) + so_kirim_baris(so_line_id=70, qty=50)
--        LOLOS → barang tercatat keluar tanpa cek Vonny dan SP terkunci (putuskan_vonny_cek menolak
--        SP yang sudah punya so_kirim). Diperbaiki di (1)–(4).
--   T3 (major) keputusan Vonny tidak terikat isi SP.
--      → SUDAH DITUTUP berkas 88 (sol_jaga_tambah, sol_vonny_gugur, so_vonny_gugur + flag
--        rhj.vonny_gugur di blok e2). Uji ulang: sales Menik tambah baris SP 45 DITOLAK; ganti
--        customer SP 45 → vonny_ok null, status 'menunggu vonny'.
--      Sisa yang masih benar: pelanggan SP yang ber-PO bisa diganti ke pelanggan lain tanpa dicek
--        terhadap PO (jaga_po_menyusul hanya memeriksa saat po_id berubah). Uji: sales Michael
--        ganti customer SP 48 (PO 53) → LOLOS (cek Vonny memang gugur, tapi SP & PO jadi beda
--        pelanggan). Diperbaiki di (5).
--   Tambahan (terkait T1): berkas 88 menjadikan dibuat_oleh penentu hak (tandai_sp_tanpa_po & so_baca),
--        padahal kolom itu masih bisa di-PATCH siapa pun yang boleh mengubah SP. Diperbaiki di (6).
--
-- Perbaikan:
--   (1) jaga_so_kirim() + trigger so_kirim_jaga (BEFORE INSERT/UPDATE/DELETE so_kirim):
--       tulis hanya selama pintu resmi terbuka (flag rhj.kirim = '1' — dinyalakan tambah_surat_jalan &
--       batal_surat_jalan). INSERT/UPDATE juga wajib: SP ada, tidak batal, vonny_ok = true,
--       kirim_ok bukan false, status_sp_hitung bukan 'menunggu gm'/'menunggu vonny'/'draft'.
--   (2) jaga_so_kirim_baris() + trigger so_kirim_baris_jaga (BEFORE INSERT/UPDATE/DELETE so_kirim_baris):
--       flag rhj.kirim wajib; baris harus barang aktif (tidak batal, bukan 'biaya') milik SP surat jalan
--       itu; qty kumulatif ≤ qty pesan (sama seperti cek sisa di RPC).
--   (3) tambah_surat_jalan: kunci SP (FOR UPDATE — dua surat jalan serentak tidak sama-sama lolos cek
--       sisa), pakai status HITUNG (kolom status bisa basi), tolak SP yang invoicenya sudah terbit atau
--       yang sudah dikirim sekaligus lewat nomor surat jalan di kepala SP (tanpa so_kirim — dulu sisa
--       terbaca penuh sehingga barang bisa "dikirim" dua kali). Flag rhj.kirim dinyalakan sebelum
--       INSERT so_kirim. Sisa fungsi identik dengan versi live (berkas 76).
--   (4) batal_surat_jalan: kunci SP, nyalakan rhj.kirim sebelum DELETE so_kirim (cascade baris ikut
--       lewat pintu). Pesan & perilaku lain identik.
--   (5) jaga_pelanggan_sp_po() + constraint trigger so_pelanggan_po (sales_orders, UPDATE OF customer_id)
--       dan po_pelanggan_sp (purchase_orders, UPDATE OF customer_id): pelanggan SP yang ber-PO harus sama
--       dengan pelanggan PO-nya (bila keduanya terisi, SP tidak batal). DEFERRABLE INITIALLY DEFERRED:
--       diperiksa saat COMMIT, jadi perapian/penggabungan pelanggan yang mengubah PO & SP dalam satu
--       transaksi tidak tersandung urutan UPDATE.
--   (6) jaga_pembuat_sp() + trigger so_jaga_pembuat (BEFORE UPDATE sales_orders, WHEN dibuat_oleh/
--       dibuat_pada berubah): hanya owner/GM. dibuat_oleh diisi so_audit saat INSERT (= auth.uid()).
--   (7) Hardening: cabut EXECUTE fungsi trigger baru dari public/anon (pola berkas 84).
--
-- RLS so_kirim/so_kirim_baris TIDAK diubah: FE hanya MEMBACA kedua tabel; tulis selalu lewat RPC.
-- Konsekuensi: SQL admin (tanpa JWT) yang menulis so_kirim/so_kirim_baris langsung harus menyalakan
--   select set_config('rhj.kirim','1',true) di transaksinya; dibuat_oleh SP tidak bisa diubah dari SQL
--   admin tanpa JWT owner/GM — sama seperti kolom gerbang lain.
-- Data: tidak ada data yang diubah (DEV: so_kirim & so_kirim_baris kosong; tak ada SP yang pelanggannya
--   beda dengan pelanggan PO-nya; status semua SP = status_sp_hitung).
-- Produksi: menuntut berkas 76, 82, 83, 86, 88 sudah terpasang. Sebelum memasang, periksa:
--   select s.id, s.no_sp from sales_orders s join so_kirim k on k.so_id = s.id where s.vonny_ok is not true;
--   select s.id, s.no_sp from sales_orders s join purchase_orders p on p.id = s.po_id
--    where not s.batal and s.customer_id <> p.customer_id;
-- Uji sesudah berkas ini (DEV, begin…rollback, tanpa sisa data):
--   Liesian INSERT so_kirim/so_kirim_baris langsung (SP 57 menunggu Vonny, SP 48 sudah lolos) → DITOLAK;
--   UPDATE so_kirim_baris / DELETE so_kirim langsung → DITOLAK; owner INSERT so_kirim langsung → DITOLAK;
--   tambah_surat_jalan SP 57 sebelum lolos → DITOLAK; sales Arie PATCH vonny_ok / panggil putuskan_vonny_cek
--   → DITOLAK; Vonny meloloskan SP 57 → status 'di gudang' (keluar dari antrean Double Check, tampil di
--   Pengiriman) → tambah_surat_jalan qty 10/50 LOLOS; Vonny menahan sesudahnya → DITOLAK (sudah dikirim);
--   SP 48: kirim 1/4 LOLOS, 5 > sisa 3 DITOLAK, 3/3 LOLOS (no_surat_jalan terisi), batal_surat_jalan LOLOS
--   (no_surat_jalan kosong lagi, SJ pertama tetap); SP 50 dikirim sekaligus oleh owner → tambah_surat_jalan
--   DITOLAK; sales Michael ganti customer SP 48 (PO pelanggan 65) → DITOLAK; owner ganti lalu kembalikan
--   dalam satu transaksi → LOLOS; ganti pelanggan PO 56 + SP 51 bersamaan → LOLOS; ganti PO 58 saja →
--   DITOLAK; sales Arie ganti dibuat_oleh → DITOLAK; owner PATCH SP tanpa ubah pembuat → LOLOS.

-- (1) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_so_kirim()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s record; v_status text;
begin
  if coalesce(current_setting('rhj.kirim', true), '') <> '1' then
    raise exception 'Surat jalan bertahap hanya bisa diterbitkan atau dibatalkan lewat panel Pengiriman '
                    '(tambah_surat_jalan / batal_surat_jalan) — tidak bisa ditulis langsung.'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  select * into s from public.sales_orders where id = new.so_id;
  if s.id is null then return new; end if;   -- FK yang menolak
  v_status := public.status_sp_hitung(s.id);
  if s.batal then
    raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode = '23514';
  end if;
  if s.vonny_ok is not true or v_status = 'menunggu vonny' then
    raise exception 'Surat Pesanan % belum di-cek & dinyatakan layak oleh Vonny — barangnya belum boleh keluar.', s.no_sp
      using errcode = '42501';
  end if;
  if v_status = 'menunggu gm' then
    raise exception 'Surat Pesanan % masih menunggu keputusan GM.', s.no_sp using errcode = '23514';
  end if;
  if v_status = 'draft' then
    raise exception 'Surat Pesanan % belum punya baris barang.', s.no_sp using errcode = '23514';
  end if;
  if s.kirim_ok is false then
    raise exception 'Pengiriman Surat Pesanan % ditahan.', s.no_sp using errcode = '23514';
  end if;
  return new;
end $function$;

drop trigger if exists so_kirim_jaga on public.so_kirim;
create trigger so_kirim_jaga
  before insert or update or delete on public.so_kirim
  for each row execute function public.jaga_so_kirim();

-- (2) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_so_kirim_baris()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_so bigint; l record; v_kirim numeric;
begin
  if coalesce(current_setting('rhj.kirim', true), '') <> '1' then
    raise exception 'Qty surat jalan bertahap hanya bisa dicatat lewat panel Pengiriman '
                    '(tambah_surat_jalan / batal_surat_jalan) — tidak bisa ditulis langsung.'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  select k.so_id into v_so from public.so_kirim k where k.id = new.kirim_id;
  select * into l from public.sales_order_lines where id = new.so_line_id;
  if v_so is null or l.id is null then return new; end if;   -- FK yang menolak
  if l.so_id is distinct from v_so or coalesce(l.batal, false) or l.jenis = 'biaya' then
    raise exception 'Baris #% bukan bagian barang aktif Surat Pesanan surat jalan ini.', new.so_line_id
      using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    select coalesce(sum(kb.qty), 0) into v_kirim
      from public.so_kirim_baris kb where kb.so_line_id = new.so_line_id and kb.id <> old.id;
  else
    select coalesce(sum(kb.qty), 0) into v_kirim
      from public.so_kirim_baris kb where kb.so_line_id = new.so_line_id;
  end if;
  if v_kirim + new.qty > l.qty then
    raise exception 'Qty kirim baris #% (%) melebihi sisa (%).', new.so_line_id, new.qty, l.qty - v_kirim
      using errcode = '23514';
  end if;
  return new;
end $function$;

drop trigger if exists so_kirim_baris_jaga on public.so_kirim_baris;
create trigger so_kirim_baris_jaga
  before insert or update or delete on public.so_kirim_baris
  for each row execute function public.jaga_so_kirim_baris();

-- (3) ─────────────────────────────────────────────────────────────────────────
create or replace function public.tambah_surat_jalan(p_so bigint, p_no text, p_tgl date, p_baris jsonb, p_catatan text default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record; v_kirim bigint; r jsonb; v_line bigint; v_qty numeric; v_sisa numeric; v_lengkap boolean; v_ada boolean;
        v_status text;
begin
  if not public.boleh_terbitkan() then
    raise exception 'Hanya owner, GM, atau Lie Sian yang boleh menerbitkan surat jalan.' using errcode='42501';
  end if;
  -- #8 berkas 89: kunci SP — dua surat jalan serentak tidak boleh sama-sama lolos cek sisa.
  select * into v from public.sales_orders where id = p_so for update;
  if v.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002'; end if;
  if v.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', v.no_sp using errcode='23514'; end if;
  v_status := public.status_sp_hitung(p_so);          -- #8 berkas 89: kolom status bisa basi
  if v_status = 'menunggu gm' then
    raise exception 'Surat Pesanan % masih menunggu keputusan GM.', v.no_sp using errcode='23514'; end if;
  if v.kirim_ok is false then
    raise exception 'Pengiriman Surat Pesanan % ditahan.', v.no_sp using errcode='23514'; end if;
  if v.vonny_ok is not true then
    raise exception 'Surat Pesanan % belum di-cek & dinyatakan layak oleh Vonny.', v.no_sp using errcode='42501'; end if;
  if v.no_invoice is not null then
    raise exception 'Invoice Surat Pesanan % sudah terbit — tidak ada lagi barang yang bisa dikirim.', v.no_sp
      using errcode='23514'; end if;
  if v.no_surat_jalan is not null and not exists (select 1 from public.so_kirim k where k.so_id = p_so) then
    raise exception 'Surat Pesanan % sudah dikirim sekaligus dengan surat jalan %. Pengiriman bertahap tidak bisa ditambahkan.',
      v.no_sp, v.no_surat_jalan using errcode='23514'; end if;
  if coalesce(btrim(p_no),'') = '' then raise exception 'No surat jalan wajib diisi.' using errcode='22023'; end if;
  if p_tgl is null then raise exception 'Tanggal surat jalan wajib diisi.' using errcode='22023'; end if;
  if p_baris is null or jsonb_array_length(p_baris) = 0 then
    raise exception 'Pilih minimal satu baris beserta qty yang dikirim.' using errcode='22023'; end if;

  -- #8 berkas 89: so_kirim/so_kirim_baris hanya bisa ditulis selama pintu ini terbuka.
  perform set_config('rhj.kirim','1',true);
  insert into public.so_kirim(so_id, no_surat_jalan, tgl, catatan)
    values (p_so, btrim(p_no), p_tgl, p_catatan) returning id into v_kirim;

  v_ada := false;
  for r in select * from jsonb_array_elements(p_baris) loop
    v_line := (r->>'so_line_id')::bigint;
    v_qty  := (r->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then continue; end if;
    select sisa into v_sisa from public.so_kirim_sisa where so_line_id = v_line and so_id = p_so;
    if v_sisa is null then
      raise exception 'Baris #% bukan bagian barang aktif Surat Pesanan ini.', v_line using errcode='23514'; end if;
    if v_qty > v_sisa then
      raise exception 'Qty kirim baris #% (%) melebihi sisa (%).', v_line, v_qty, v_sisa using errcode='23514'; end if;
    insert into public.so_kirim_baris(kirim_id, so_line_id, qty) values (v_kirim, v_line, v_qty);
    v_ada := true;
  end loop;
  if not v_ada then
    raise exception 'Tidak ada qty yang dikirim. Isi qty > 0 untuk minimal satu baris.' using errcode='22023'; end if;

  select coalesce(bool_and(sisa <= 0), true) into v_lengkap from public.so_kirim_sisa where so_id = p_so;
  if v_lengkap then
    update public.sales_orders set no_surat_jalan = btrim(p_no), tgl_surat_jalan = p_tgl where id = p_so;
  end if;
  perform set_config('rhj.kirim','',true);
  if v_lengkap then
    return 'Surat jalan ' || btrim(p_no) || ' terbit. SEMUA barang sudah terkirim — invoice boleh diterbitkan.';
  end if;
  return 'Surat jalan ' || btrim(p_no) || ' terbit (pengiriman bertahap). Masih ada sisa barang yang belum dikirim.';
end $function$;

-- (4) ─────────────────────────────────────────────────────────────────────────
create or replace function public.batal_surat_jalan(p_kirim bigint)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record; v_so bigint; v_lengkap boolean;
begin
  if not public.boleh_terbitkan() then
    raise exception 'Hanya owner, GM, atau Lie Sian yang boleh membatalkan surat jalan.' using errcode='42501';
  end if;
  -- #8 berkas 89: kunci SP-nya (serentak dengan tambah_surat_jalan / invoice).
  select k.*, s.no_invoice, s.no_sp into v
    from public.so_kirim k join public.sales_orders s on s.id = k.so_id
   where k.id = p_kirim
     for update of s;
  if v.id is null then raise exception 'Surat jalan tidak ditemukan.' using errcode='P0002'; end if;
  if v.no_invoice is not null then
    raise exception 'Invoice Surat Pesanan % sudah terbit — batalkan invoicenya dulu.', v.no_sp using errcode='23514'; end if;
  v_so := v.so_id;
  perform set_config('rhj.kirim','1',true);          -- #8 berkas 89: pintu so_kirim (cascade baris ikut)
  delete from public.so_kirim where id = p_kirim;   -- cascade baris

  select coalesce(bool_and(sisa <= 0), false) into v_lengkap from public.so_kirim_sisa where so_id = v_so;
  if not v_lengkap then
    update public.sales_orders set no_surat_jalan = null, tgl_surat_jalan = null
      where id = v_so and no_surat_jalan is not null;
  end if;
  perform set_config('rhj.kirim','',true);
  return 'Surat jalan dibatalkan.';
end $function$;

-- (5) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_pelanggan_sp_po()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  -- Dibaca ulang dari tabel (bukan NEW): pemeriksaan ditunda sampai COMMIT, jadi yang dinilai
  -- keadaan akhir transaksi.
  for r in
    select s.no_sp, p.no_po
      from public.sales_orders s
      join public.purchase_orders p on p.id = s.po_id
     where (case when tg_table_name = 'sales_orders' then s.id = new.id else p.id = new.id end)
       and not s.batal
       and s.customer_id is not null and p.customer_id is not null
       and s.customer_id <> p.customer_id
     limit 1
  loop
    raise exception
      'Pelanggan Surat Pesanan % tidak sama dengan pelanggan PO % yang ditempelkan. Pesanan satu '
      'pelanggan tidak boleh ditagihkan atas PO pelanggan lain — kembalikan pelanggannya, atau '
      'ganti PO-nya lewat "Minta ubah SP".', r.no_sp, r.no_po
      using errcode = '23514';
  end loop;
  return null;
end $function$;

drop trigger if exists so_pelanggan_po on public.sales_orders;
create constraint trigger so_pelanggan_po
  after update of customer_id on public.sales_orders
  deferrable initially deferred
  for each row
  when (old.customer_id is distinct from new.customer_id and new.po_id is not null)
  execute function public.jaga_pelanggan_sp_po();

drop trigger if exists po_pelanggan_sp on public.purchase_orders;
create constraint trigger po_pelanggan_sp
  after update of customer_id on public.purchase_orders
  deferrable initially deferred
  for each row
  when (old.customer_id is distinct from new.customer_id)
  execute function public.jaga_pelanggan_sp_po();

-- (6) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_pembuat_sp()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if public.setara_owner() then return new; end if;
  raise exception
    'Pembuat Surat Pesanan % dicatat sistem saat SP dibuat dan tidak bisa diubah — ia menentukan siapa '
    'yang boleh menyatakan mode tanpa PO dan melihat SP selama cek Vonny.', coalesce(new.no_sp, '(baru)')
    using errcode = '42501';
end $function$;

drop trigger if exists so_jaga_pembuat on public.sales_orders;
create trigger so_jaga_pembuat
  before update on public.sales_orders
  for each row
  when (old.dibuat_oleh is distinct from new.dibuat_oleh or old.dibuat_pada is distinct from new.dibuat_pada)
  execute function public.jaga_pembuat_sp();

-- (7) ─────────────────────────────────────────────────────────────────────────
revoke execute on function public.jaga_so_kirim()        from public, anon;
revoke execute on function public.jaga_so_kirim_baris()  from public, anon;
revoke execute on function public.jaga_pelanggan_sp_po() from public, anon;
revoke execute on function public.jaga_pembuat_sp()      from public, anon;
