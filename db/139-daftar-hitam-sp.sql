-- ═══════════════════════════════════════════════════════════════════════
-- 139 · Temuan keamanan #7 (keputusan Hannes 9 Okt, no. 14–16): daftar hitam berlaku di SP, bukan hanya di PO
--
-- Celah (uji DEV): daftar hitam hanya dijaga trigger po_jaga_blacklist (PO baru / ganti pelanggan PO). Tidak ada penjaga
-- di SP: SP tanpa PO bisa dibuat untuk pelanggan daftar hitam (memilihnya dari daftar, atau mengetik namanya tanpa
-- memilih), SP lama milik pelanggan yang kemudian masuk daftar hitam tetap bisa dikirim (surat jalan sekaligus maupun
-- bertahap; izin kirim Vonny/GM pun tidak dibutuhkan), dan cek Vonny hanya menahan kasus sempit "PO belum bertuan"
-- (berkas 121). Status daftar hitam & "konfirmasi sebelum kirim" bisa diubah sales/staff (untuk pelanggan yang boleh ia
-- ubah) — sales bisa mencabut daftar hitam lalu membuat PO/SP.
--
-- Perbaikan (selain jalur tanpa sesi: migrasi / SQL Editor / service role — apa adanya):
--  (1) sp_pelanggan_hitam(customer, po, kepada, telp): pelanggan daftar hitam milik SP — pelanggan SP (atau pelanggan
--      PO-nya bila SP belum tertaut); SP yang belum tertaut sama sekali dicocokkan nama (kunci_nama_pelanggan, nama &
--      nama asli) lalu No. HP ke pelanggan daftar hitam. Fungsi internal (tidak bisa dipanggil lewat REST).
--  (2) (no. 14) SP baru / SP batal yang dihidupkan lagi untuk pelanggan daftar hitam ditolak — semua peran bila
--      pelanggannya tertaut (sama dengan PO); bila hanya cocok nama/No. HP, ditolak untuk selain owner/GM (beri
--      pembeda pada nama bila memang perusahaan lain). RPC sp_daftar_hitam_cek untuk layar: diperiksa SEBELUM nomor SP
--      diambil (nomor tidak hangus); pesan untuk kecocokan nama tidak menyebut pelanggannya.
--  (3) (no. 14 & 16) Barang SP pelanggan daftar hitam DITAHAN TOTAL: gerbang_kirim_sp (setiap surat jalan bertahap) dan
--      jaga_urutan_dokumen_sp (surat jalan sekaligus) menolak surat jalan — izin kirim Vonny/GM tidak membukanya.
--      Invoice, faktur, pelunasan, dan penutupan surat jalan bertahap yang sudah terbit (rhj.sj_final — mis. sisa
--      dibatalkan) tetap jalan.
--  (4) cek_kelayakan_vonny menampilkan alasan 'blacklist' (siapa: owner/GM) untuk semua SP di atas, dan
--      putuskan_vonny_cek menolak meloloskannya (semua peran). "Tahan" tetap bisa.
--  (5) (no. 15) Daftar hitam & "konfirmasi sebelum kirim" (beserta alasannya) hanya diubah owner/GM — trigger
--      customers_jaga_status; peran lain tidak bisa mengisinya saat membuat pelanggan maupun mengubahnya. Daftar hitam
--      wajib beralasan (sama dengan konfirmasi, CHECK cust_konfirmasi_beralasan).
-- Pesan penolakan P0001/22023/23514 (bukan 42501 — tidak memicu batas tolak 401/403 di layar).
-- Fungsi panjang (jaga_urutan_dokumen_sp, cek_kelayakan_vonny, putuskan_vonny_cek) diubah dengan sisip teks pada
-- definisi hidup + pemeriksaan jangkar (berhenti bila bentuknya tidak seperti yang diharapkan).
-- Tidak menyentuh objek EHC/komisi. Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139r/139s/139w/139x/139y/139z (review 139y no. 5): menjalankannya ulang sendirian
--      menurunkan fungsi yang diperbarui berkas sesudahnya. Menjalankan ulang seluruh rantai 138 → berkas terakhir
--      berurutan dalam satu transaksi: `begin; set local rhj.ulang_rantai = 'on';` … `commit;`.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '139: berkas ini sudah disusul berkas sesudahnya — jangan dijalankan ulang sendirian (jalankan ulang '
                    'seluruh rantai 138 → berkas terakhir berurutan dalam satu transaksi sesudah set local rhj.ulang_rantai = ''on'').';
  end if;
end $$;

-- (1)
create or replace function public.sp_pelanggan_hitam(p_customer bigint, p_po bigint, p_kepada text, p_telp text)
returns bigint language plpgsql stable security definer set search_path = public as $$
declare v_c bigint := p_customer; v_k text; v_hp text; v_id bigint;
begin
  if v_c is null and p_po is not null then
    select p.customer_id into v_c from public.purchase_orders p where p.id = p_po;
  end if;
  if v_c is not null then
    select c.id into v_id from public.customers c where c.id = v_c and c.blacklist;
    return v_id;                                   -- tertaut: hanya pelanggan itu yang menentukan
  end if;
  v_k := public.kunci_nama_pelanggan(p_kepada);
  if char_length(coalesce(v_k, '')) >= 2 then
    select c.id into v_id from public.customers c
     where c.blacklist
       and (public.kunci_nama_pelanggan(c.nama) = v_k
            or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k))
     order by c.id limit 1;
    if v_id is not null then return v_id; end if;
  end if;
  v_hp := public.hp_baku(p_telp);
  if v_hp is not null then
    select c.id into v_id from public.customers c where c.blacklist and c.hp = v_hp order by c.id limit 1;
  end if;
  return v_id;
end $$;
comment on function public.sp_pelanggan_hitam(bigint, bigint, text, text) is
  '139 (temuan #7): pelanggan daftar hitam milik SP — pelanggan SP/PO-nya, atau (SP belum tertaut) cocok nama/No. HP.';
revoke all on function public.sp_pelanggan_hitam(bigint, bigint, text, text) from public, anon, authenticated;

-- pesan bersama gerbang surat jalan (dipanggil dari fungsi/trigger SECURITY DEFINER)
create or replace function public.tahan_daftar_hitam_sp(p_no_sp text, p_customer bigint, p_po bigint, p_kepada text,
                                                        p_telp text)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_id bigint; v_c public.customers; v_tertaut boolean;
begin
  v_id := public.sp_pelanggan_hitam(p_customer, p_po, p_kepada, p_telp);
  if v_id is null then return; end if;
  select * into v_c from public.customers where id = v_id;
  v_tertaut := p_customer is not null
               or (p_po is not null and exists (select 1 from public.purchase_orders p
                                                 where p.id = p_po and p.customer_id is not null));
  if v_tertaut then
    raise exception 'Pelanggan Surat Pesanan % ("%") masuk daftar hitam (%). Barangnya ditahan total — izin kirim tidak '
                    'membukanya. Owner/GM mencabut daftar hitamnya di tab Pelanggan, atau membatalkan sisa SP. Invoice dan '
                    'pelunasan barang yang sudah keluar tetap bisa.',
      coalesce(p_no_sp, '(baru)'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
  end if;
  raise exception 'Nama/No. HP Surat Pesanan % cocok dengan pelanggan daftar hitam "%" (%). Barangnya ditahan. Bila ini '
                  'perusahaan/orang lain, owner/GM menautkan SP ke data pelanggan yang benar dulu (detail SP).',
    coalesce(p_no_sp, '(baru)'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
end $$;
revoke all on function public.tahan_daftar_hitam_sp(text, bigint, bigint, text, text) from public, anon, authenticated;

-- (2) SP baru / dihidupkan lagi
create or replace function public.jaga_daftar_hitam_sp()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_c public.customers; v_link bigint;
begin
  if auth.uid() is null then return new; end if;            -- migrasi / SQL Editor / service role
  if new.batal then return new; end if;
  if tg_op = 'UPDATE' and not (old.batal and not new.batal) then return new; end if;
  v_id := public.sp_pelanggan_hitam(new.customer_id, new.po_id, new.kepada, new.telp);
  if v_id is null then return new; end if;
  select * into v_c from public.customers where id = v_id;
  v_link := coalesce(new.customer_id, (select p.customer_id from public.purchase_orders p where p.id = new.po_id));
  if v_link is not null then
    raise exception 'Pelanggan "%" masuk daftar hitam (%). Surat Pesanan tidak bisa dibuat atau dihidupkan lagi untuknya — '
                    'owner/GM mencabut daftar hitamnya dulu di tab Pelanggan bila memang boleh dilayani lagi.',
      v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan');
  end if;
  if not public.setara_owner() then
    raise exception 'Nama/No. HP "%" cocok dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. '
                    'Bila ini perusahaan/orang lain, beri pembeda pada namanya (mis. kota atau cabang), atau minta owner/GM.',
      coalesce(new.kepada, '');
  end if;
  return new;   -- owner/GM: boleh dibuat; barangnya tetap tertahan sampai SP ditautkan ke pelanggan yang benar
end $$;
revoke all on function public.jaga_daftar_hitam_sp() from public, anon, authenticated;
create or replace trigger so_jaga_b_daftar_hitam
  before insert or update of batal on public.sales_orders
  for each row execute function public.jaga_daftar_hitam_sp();

-- (2) pemeriksaan layar sebelum nomor SP diambil (ya/tidak + pesan; kecocokan nama tidak menyebut pelanggannya)
create or replace function public.sp_daftar_hitam_cek(p_customer bigint default null, p_po bigint default null,
                                                      p_kepada text default null, p_telp text default null)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_id bigint; v_c public.customers; v_link bigint;
begin
  if auth.uid() is null or not (public.boleh_alur_jual() or public.boleh_konfirmasi_kirim()) then return null; end if;
  v_id := public.sp_pelanggan_hitam(p_customer, p_po, p_kepada, p_telp);
  if v_id is null then return null; end if;
  v_link := coalesce(p_customer, (select p.customer_id from public.purchase_orders p where p.id = p_po));
  if v_link is not null then
    select * into v_c from public.customers where id = v_id;
    -- pelanggan yang dipilih sendiri / pelanggan PO miliknya: boleh disebut
    if public.peran_saya() <> 'sales' or public.pic_pelanggan_saya(v_id) then
      return 'Pelanggan "' || v_c.nama || '" masuk daftar hitam (' || coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
          || '). Surat Pesanan tidak bisa dibuat untuknya — owner/GM mencabut daftar hitamnya dulu bila memang boleh dilayani lagi.';
    end if;
    return 'Pelanggan SP ini masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Hubungi owner/GM.';
  end if;
  if public.setara_owner() then return null; end if;
  return 'Nama/No. HP ini cocok dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Bila ini '
      || 'perusahaan/orang lain, beri pembeda pada namanya (mis. kota atau cabang), atau minta owner/GM.';
end $$;
revoke all on function public.sp_daftar_hitam_cek(bigint, bigint, text, text) from public, anon;
grant execute on function public.sp_daftar_hitam_cek(bigint, bigint, text, text) to authenticated;

-- (3) gerbang surat jalan bertahap — definisi berkas 97 + gerbang 0 daftar hitam
create or replace function public.gerbang_kirim_sp(p_so bigint)
returns void language plpgsql stable security definer set search_path = public as $function$
declare s record; v_tahan boolean; v_perlu boolean;
begin
  select * into s from public.sales_orders where id = p_so;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode='23514'; end if;
  if not exists (select 1 from public.sales_order_lines l where l.so_id = p_so) then
    raise exception 'Surat Pesanan % belum punya baris barang.', s.no_sp using errcode='23514'; end if;
  -- gerbang 0 (139, keputusan Hannes 9 Okt no. 14): pelanggan daftar hitam → ditahan total, izin kirim tidak membukanya
  perform public.tahan_daftar_hitam_sp(s.no_sp, s.customer_id, s.po_id, s.kepada, s.telp);
  if s.vonny_ok is not true then
    raise exception 'Surat Pesanan % belum di-cek & dinyatakan layak oleh Vonny — barangnya belum boleh keluar.', s.no_sp
      using errcode='42501'; end if;
  if s.kirim_ok is false then
    raise exception 'Pengiriman Surat Pesanan % ditahan%.', s.no_sp, coalesce(' — ' || s.kirim_alasan, '')
      using errcode='23514'; end if;
  -- gerbang 1 (cermin jaga_urutan_dokumen_sp): harga di bawah price list belum diputus GM
  select coalesce(r.ada_bawah_list, false) and s.harga_ok is not true into v_tahan
    from public.so_ringkas r where r.so_id = p_so;
  if coalesce(v_tahan, false) then
    raise exception 'Surat Pesanan % masih menunggu keputusan GM karena ada harga di bawah price list. '
                    'Surat jalan (termasuk pengiriman sebagian) belum boleh terbit.', s.no_sp using errcode='23514'; end if;
  -- gerbang 2: pelanggan perlu konfirmasi sebelum kirim
  select coalesce(c.perlu_konfirmasi, false) into v_perlu from public.customers c where c.id = s.customer_id;
  if coalesce(v_perlu, false) and s.kirim_ok is not true then
    raise exception 'Pelanggan Surat Pesanan % ditandai perlu konfirmasi sebelum pengiriman. Vonny atau GM harus '
                    'mengizinkan dulu — berlaku juga untuk pengiriman sebagian.', s.no_sp using errcode='23514'; end if;
  -- gerbang 3a: barang keluar tanpa PO harus dinyatakan
  if s.po_id is null and not s.po_menyusul and not s.tanpa_po_ok then
    raise exception 'Surat Pesanan % belum punya PO. Tandai "PO menyusul" beserta alasannya sebelum surat jalan '
                    'PERTAMA (termasuk pengiriman sebagian).', s.no_sp using errcode='23514'; end if;
end $function$;

-- (3) surat jalan sekaligus · (4) cek Vonny · (4) putuskan cek Vonny — sisip pada definisi hidup
do $$
declare
  v text; w text;
  a1 text := '-- gerbang 2: pelanggan yang perlu dikonfirmasi sebelum kirim (berkas 41)';
  s1 text := $s1$-- gerbang 0 (139, keputusan Hannes 9 Okt no. 14 & 16): pelanggan daftar hitam → SURAT JALAN ditahan total
    -- (izin kirim tidak membukanya). Invoice/faktur/pelunasan barang yang sudah keluar, dan penutupan surat jalan
    -- bertahap yang sudah terbit (rhj.sj_final, mis. sisa dibatalkan), tetap jalan.
    if new.no_surat_jalan is not null
       and (tg_op = 'INSERT' or new.no_surat_jalan is distinct from old.no_surat_jalan)
       and coalesce(current_setting('rhj.sj_final', true), '') <> '1' then
      perform public.tahan_daftar_hitam_sp(new.no_sp, new.customer_id, new.po_id, new.kepada, new.telp);
    end if;

    $s1$;
  a2 text := '    -- 135 · pelanggan diisi dari PO yang ditempel menyusul';
  s2 text := $s2$    -- 139 · pelanggan daftar hitam (keputusan Hannes 9 Okt no. 14): ditahan total — semua peran
    v_hitam := public.sp_pelanggan_hitam(s.customer_id, s.po_id, s.kepada,
                                         coalesce(nullif(btrim(coalesce(p_hp, '')), ''), s.telp));
    if v_hitam is not null then
      select c.nama, c.alasan_blacklist into v_hitam_nama, v_hitam_alasan from public.customers c where c.id = v_hitam;
      kode := 'blacklist'; siapa := 'owner/GM';
      pesan := case when s.customer_id is not null or s.po_id is not null and exists (
                           select 1 from public.purchase_orders p where p.id = s.po_id and p.customer_id is not null)
                    then 'Pelanggan "' || v_hitam_nama || '" masuk daftar hitam ('
                    else 'Nama/No. HP SP ini cocok dengan pelanggan daftar hitam "' || v_hitam_nama || '" (' end
            || coalesce(v_hitam_alasan, 'tanpa keterangan') || ') — SP ini ditahan total.';
      tindakan := 'Owner/GM memutuskan: cabut daftar hitam pelanggan di tab Pelanggan, atau batalkan SP ini'
               || case when s.customer_id is null then '; bila ini perusahaan lain, tautkan SP ke data pelanggan yang benar.'
                       else '.' end;
      return next; continue;
    end if;

$s2$;
  a2d text := '  v_sales_po text;';
  s2d text := '  v_sales_po text;
  v_hitam        bigint;   -- 139
  v_hitam_nama   text;
  v_hitam_alasan text;';
  a3 text := '  if p_ok is false and coalesce(btrim(p_alasan),'''') = '''' then';
  s3 text := $s3$  -- 139 (keputusan Hannes 9 Okt no. 14): SP pelanggan daftar hitam tidak bisa diloloskan (semua peran)
  if p_ok and public.sp_pelanggan_hitam(v.customer_id, v.po_id, v.kepada, v.telp) is not null then
    raise exception 'Surat Pesanan % belum bisa diloloskan: pelanggannya (atau nama/No. HP-nya) masuk daftar hitam. '
                    'Owner/GM mencabut daftar hitamnya, membatalkan SP, atau menautkan SP ke pelanggan yang benar.', v.no_sp
      using errcode='22023';
  end if;
$s3$;
  n int;
begin
  -- jaga_urutan_dokumen_sp
  v := pg_get_functiondef('public.jaga_urutan_dokumen_sp()'::regprocedure);
  if position('tahan_daftar_hitam_sp' in v) = 0 then
    n := (length(v) - length(replace(v, a1, ''))) / length(a1);
    if n <> 1 then raise exception '139: jaga_urutan_dokumen_sp — jangkar gerbang 2 tidak 1 (%).', n; end if;
    execute replace(v, a1, s1 || a1);
  end if;

  -- cek_kelayakan_vonny
  v := pg_get_functiondef('public.cek_kelayakan_vonny(bigint, text, text)'::regprocedure);
  if position('v_hitam' in v) = 0 then
    n := (length(v) - length(replace(v, a2, ''))) / length(a2);
    if n <> 1 then raise exception '139: cek_kelayakan_vonny — jangkar 135 tidak 1 (%).', n; end if;
    n := (length(v) - length(replace(v, a2d, ''))) / length(a2d);
    if n <> 1 then raise exception '139: cek_kelayakan_vonny — jangkar deklarasi tidak 1 (%).', n; end if;
    w := replace(replace(v, a2, s2 || a2), a2d, s2d);
    execute w;
  end if;

  -- putuskan_vonny_cek
  v := pg_get_functiondef('public.putuskan_vonny_cek(bigint, boolean, text)'::regprocedure);
  if position('sp_pelanggan_hitam' in v) = 0 then
    n := (length(v) - length(replace(v, a3, ''))) / length(a3);
    if n <> 1 then raise exception '139: putuskan_vonny_cek — jangkar alasan tahan tidak 1 (%).', n; end if;
    execute replace(v, a3, s3 || a3);
  end if;
end $$;

-- (5) status daftar hitam & konfirmasi sebelum kirim: owner/GM saja
create or replace function public.customers_jaga_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;            -- migrasi / SQL Editor / service role
  if not public.setara_owner() then
    if (tg_op = 'INSERT' and (coalesce(new.blacklist, false) or coalesce(new.perlu_konfirmasi, false)
                              or coalesce(btrim(new.alasan_blacklist), '') <> ''
                              or coalesce(btrim(new.alasan_konfirmasi), '') <> ''))
       or (tg_op = 'UPDATE' and (new.blacklist is distinct from old.blacklist
                                 or new.alasan_blacklist is distinct from old.alasan_blacklist
                                 or new.perlu_konfirmasi is distinct from old.perlu_konfirmasi
                                 or new.alasan_konfirmasi is distinct from old.alasan_konfirmasi)) then
      raise exception 'Status pelanggan "Daftar hitam" dan "Konfirmasi sebelum kirim" (beserta alasannya) hanya diubah '
                      'owner atau GM.';
    end if;
    return new;
  end if;
  if coalesce(new.blacklist, false) and coalesce(btrim(new.alasan_blacklist), '') = ''
     and (tg_op = 'INSERT' or new.blacklist is distinct from old.blacklist
          or new.alasan_blacklist is distinct from old.alasan_blacklist) then
    raise exception 'Alasan daftar hitam wajib diisi — alasannya yang muncul saat PO/SP pelanggan ini ditolak.';
  end if;
  return new;
end $$;
revoke all on function public.customers_jaga_status() from public, anon, authenticated;
create or replace trigger customers_jaga_status
  before insert or update of blacklist, alasan_blacklist, perlu_konfirmasi, alasan_konfirmasi on public.customers
  for each row execute function public.customers_jaga_status();

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass and tgname = 'so_jaga_b_daftar_hitam')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'customers_jaga_status') then
    raise exception '139: trigger daftar hitam belum terpasang';
  end if;
  if position('tahan_daftar_hitam_sp' in pg_get_functiondef('public.jaga_urutan_dokumen_sp()'::regprocedure)) = 0
     or position('tahan_daftar_hitam_sp' in pg_get_functiondef('public.gerbang_kirim_sp(bigint)'::regprocedure)) = 0
     or position('v_hitam' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint, text, text)'::regprocedure)) = 0
     or position('sp_pelanggan_hitam' in pg_get_functiondef('public.putuskan_vonny_cek(bigint, boolean, text)'::regprocedure)) = 0 then
    raise exception '139: gerbang daftar hitam belum lengkap';
  end if;
  if has_function_privilege('authenticated', 'public.sp_pelanggan_hitam(bigint, bigint, text, text)', 'execute')
     or has_function_privilege('anon', 'public.sp_daftar_hitam_cek(bigint, bigint, text, text)', 'execute') then
    raise exception '139: hak fungsi daftar hitam belum dipersempit';
  end if;
end $$;
