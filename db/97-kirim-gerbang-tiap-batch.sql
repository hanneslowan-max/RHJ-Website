-- Berkas 97 (#15): pengiriman bertahap — gerbang yang sama di SETIAP surat jalan, tulis so_kirim
--   hanya lewat RPC, dan finalisasi no_surat_jalan di satu tempat.
--
-- Temuan (diverifikasi di DEV, begin…rollback):
--   (a) tambah_surat_jalan hanya menolak kirim_ok = false. jaga_urutan_dokumen_sp (gerbang 2) menolak
--       pelanggan perlu_konfirmasi dengan kirim_ok bukan true — tapi baru saat no_surat_jalan diisi,
--       yaitu di batch TERAKHIR. Batch parsial pertama lolos tanpa izin Vonny/GM.
--   (b) Gerbang 3a (SP tanpa PO wajib "PO menyusul"/tanpa_po_ok) juga baru dicek di batch terakhir:
--       batch awal lolos, batch terakhir ditolak → SP macet dengan barang sudah separuh keluar.
--   (c) Policy sokirim_tulis/sokirimb_tulis (= boleh_terbitkan()) + grant ALL untuk anon/authenticated
--       masih ada. Berkas 89 sudah memasang trigger pintu (flag rhj.kirim) sehingga INSERT langsung
--       ditolak; berkas ini menutup lapisan RLS/grant-nya juga (pertahanan berlapis).
--
-- Perbaikan:
--   (1) gerbang_kirim_sp(p_so): cermin gerbang 1, 2, 3a jaga_urutan_dokumen_sp + gerbang Vonny +
--       batal/ditahan/draft. Dipanggil tambah_surat_jalan dan trigger jaga_so_kirim di SETIAP batch.
--       >>> Bila gerbang di jaga_urutan_dokumen_sp berubah, UBAH KEDUANYA BERSAMA. <<<
--   (2) finalisasi_kirim_sp(p_so): satu-satunya tempat no_surat_jalan SP bertahap diisi/dilepas.
--       Bila ada ≥1 surat jalan dan semua sisa = 0 → no_surat_jalan/tgl = batch terakhir (aturan
--       lama tambah_surat_jalan). Bila sisa > 0 lagi → dilepas (ditolak kalau invoice sudah terbit).
--       Dipakai tambah_surat_jalan sekarang dan batalkan_baris_sp/pulihkan_baris_sp (berkas 98).
--   (3) tambah_surat_jalan: gerbang_kirim_sp + finalisasi_kirim_sp; validasi p_baris array.
--   (4) jaga_so_kirim: INSERT/UPDATE memakai gerbang_kirim_sp (jalur mana pun, gerbang sama).
--   (5) Cabut policy & grant tulis so_kirim/so_kirim_baris/view kirim. RPC SECURITY DEFINER milik
--       postgres (bypass RLS), jadi tambah_surat_jalan/batal_surat_jalan tetap jalan.
-- Data: tidak ada yang diubah (DEV: so_kirim 0 baris).

-- (1) ─────────────────────────────────────────────────────────────────────────
create or replace function public.gerbang_kirim_sp(p_so bigint)
 returns void
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare s record; v_tahan boolean; v_perlu boolean;
begin
  select * into s from public.sales_orders where id = p_so;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode='23514'; end if;
  if not exists (select 1 from public.sales_order_lines l where l.so_id = p_so) then
    raise exception 'Surat Pesanan % belum punya baris barang.', s.no_sp using errcode='23514'; end if;
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

-- (2) ─────────────────────────────────────────────────────────────────────────
-- Pemanggil sudah mengunci baris SP (FOR UPDATE).
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
    -- gerbang jaga_urutan_dokumen_sp & jaga_gerbang_vonny tetap berlaku di UPDATE ini
    update public.sales_orders set no_surat_jalan = k.no_surat_jalan, tgl_surat_jalan = k.tgl where id = p_so;
    perform set_config('rhj.kirim','',true);
    return 'lengkap';
  elsif not v_lengkap and s.no_surat_jalan is not null then
    if s.no_invoice is not null then
      raise exception 'Invoice Surat Pesanan % sudah terbit — pengiriman tidak bisa dibuka lagi.', s.no_sp
        using errcode='23514'; end if;
    perform set_config('rhj.kirim','1',true);
    update public.sales_orders set no_surat_jalan = null, tgl_surat_jalan = null where id = p_so;
    perform set_config('rhj.kirim','',true);
    return 'dibuka';
  end if;
  return case when v_lengkap then 'lengkap' else 'sisa' end;
end $function$;

-- (3) ─────────────────────────────────────────────────────────────────────────
create or replace function public.tambah_surat_jalan(p_so bigint, p_no text, p_tgl date, p_baris jsonb, p_catatan text default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record; v_kirim bigint; r jsonb; v_line bigint; v_qty numeric; v_sisa numeric; v_ada boolean; v_fin text;
begin
  if not public.boleh_terbitkan() then
    raise exception 'Hanya owner, GM, atau Lie Sian yang boleh menerbitkan surat jalan.' using errcode='42501';
  end if;
  -- kunci SP — dua surat jalan serentak / batal baris serentak tidak boleh sama-sama lolos cek sisa
  select * into v from public.sales_orders where id = p_so for update;
  if v.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002'; end if;
  if v.no_invoice is not null then
    raise exception 'Invoice Surat Pesanan % sudah terbit — tidak ada lagi barang yang bisa dikirim.', v.no_sp
      using errcode='23514'; end if;
  if v.no_surat_jalan is not null and not exists (select 1 from public.so_kirim k where k.so_id = p_so) then
    raise exception 'Surat Pesanan % sudah dikirim sekaligus dengan surat jalan %. Pengiriman bertahap tidak bisa ditambahkan.',
      v.no_sp, v.no_surat_jalan using errcode='23514'; end if;
  if v.no_surat_jalan is not null then
    raise exception 'Surat Pesanan % sudah tercatat terkirim semua (surat jalan %).', v.no_sp, v.no_surat_jalan
      using errcode='23514'; end if;
  -- #15 berkas 97: gerbang lengkap di SETIAP batch, bukan hanya batch terakhir
  perform public.gerbang_kirim_sp(p_so);
  if coalesce(btrim(p_no),'') = '' then raise exception 'No surat jalan wajib diisi.' using errcode='22023'; end if;
  if p_tgl is null then raise exception 'Tanggal surat jalan wajib diisi.' using errcode='22023'; end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' or jsonb_array_length(p_baris) = 0 then
    raise exception 'Pilih minimal satu baris beserta qty yang dikirim.' using errcode='22023'; end if;

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
  perform set_config('rhj.kirim','',true);
  if not v_ada then
    raise exception 'Tidak ada qty yang dikirim. Isi qty > 0 untuk minimal satu baris.' using errcode='22023'; end if;

  v_fin := public.finalisasi_kirim_sp(p_so);
  if v_fin = 'lengkap' then
    return 'Surat jalan ' || btrim(p_no) || ' terbit. SEMUA barang sudah terkirim — invoice boleh diterbitkan.';
  end if;
  return 'Surat jalan ' || btrim(p_no) || ' terbit (pengiriman bertahap). Masih ada sisa barang yang belum dikirim.';
end $function$;

-- (4) ─────────────────────────────────────────────────────────────────────────
create or replace function public.jaga_so_kirim()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if coalesce(current_setting('rhj.kirim', true), '') <> '1' then
    raise exception 'Surat jalan bertahap hanya bisa diterbitkan atau dibatalkan lewat panel Pengiriman '
                    '(tambah_surat_jalan / batal_surat_jalan) — tidak bisa ditulis langsung.'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if not exists (select 1 from public.sales_orders where id = new.so_id) then return new; end if;  -- FK yang menolak
  perform public.gerbang_kirim_sp(new.so_id);   -- #15 berkas 97: gerbang sama di jalur mana pun
  return new;
end $function$;

-- (5) ─────────────────────────────────────────────────────────────────────────
drop policy if exists sokirim_tulis  on public.so_kirim;
drop policy if exists sokirimb_tulis on public.so_kirim_baris;
revoke all on public.so_kirim, public.so_kirim_baris, public.so_kirim_sisa, public.so_kirim_ringkas from anon;
revoke insert, update, delete, truncate, references, trigger
  on public.so_kirim, public.so_kirim_baris, public.so_kirim_sisa, public.so_kirim_ringkas from authenticated;
grant select on public.so_kirim, public.so_kirim_baris, public.so_kirim_sisa, public.so_kirim_ringkas to authenticated;

-- (6) ─────────────────────────────────────────────────────────────────────────
revoke all on function public.gerbang_kirim_sp(bigint)    from public, anon, authenticated;  -- internal
revoke all on function public.finalisasi_kirim_sp(bigint) from public, anon, authenticated;  -- internal
revoke execute on function public.jaga_so_kirim() from public, anon;
revoke execute on function public.tambah_surat_jalan(bigint,text,date,jsonb,text), public.batal_surat_jalan(bigint) from public, anon;
grant  execute on function public.tambah_surat_jalan(bigint,text,date,jsonb,text), public.batal_surat_jalan(bigint) to authenticated;

notify pgrst, 'reload schema';
