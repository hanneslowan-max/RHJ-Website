-- Berkas 98 (#18): batal SISA qty per baris SP (bukan hanya satu baris utuh), finalisasi surat jalan
--   sesudah batal, dan PO menampilkan nilai batal/efektif.
--
-- Temuan (diverifikasi di DEV, begin…rollback):
--   (d) batalkan_baris_sp hanya bisa batal satu baris utuh — dan membolehkan batal baris yang sudah
--       terkirim sebagian: 50/200 terkirim lalu batal → baris hilang dari so_baris_hitung, 50 pcs yang
--       sudah keluar tidak tertagih.
--   (e) DEADLOCK: baris yang belum terkirim dibatalkan sehingga semua sisa 0 → no_surat_jalan tidak
--       pernah terisi (hanya diisi tambah_surat_jalan, yang menolak qty 0; isi manual ditolak
--       jaga_kirim_bertahap) → invoice tidak bisa terbit.
--   (f) PO tidak mencerminkan batal; sp_beda_po/sp_selisih_po membandingkan nilai EFEKTIF SP ke PO
--       sedangkan periksa_total_sp membandingkan nilai AWAL → alarm "SP beda PO" palsu sesudah batal.
--   (h) laporan_margin_produk/_sp & gm_konteks_keputusan membaca qty mentah (baris batal ikut).
--   (i) putuskan_ubah (SP) menghapus & menyisipkan ulang baris: pembatalan hilang diam-diam, baris
--       yang sudah ada di surat jalan → galat FK mentah.
--
-- Keputusan desain:
--   * qty_batal kumulatif per baris; qty EFEKTIF = qty − qty_batal. Kolom lama `batal` tetap ada
--     sebagai turunan "batal penuh" (qty_batal >= qty), dijaga trigger — FE/RPC lama tetap jalan.
--   * Qty yang sudah terkirim TIDAK bisa dibatalkan (lewat retur). Maks batal = qty − batal − terkirim.
--   * Invarian SP = PO dibandingkan pada nilai AWAL di kedua sisi (periksa_total_sp & po_ringkas tidak
--     diubah; PO = dokumen pelanggan). Nilai efektif diturunkan: SP → so_ringkas, PO → po_batal_ringkas
--     (PO − Σ nilai_batal SP-nya). sp_beda_po & sp_selisih_po disamakan ke nilai awal.
--   * Pembatalan yang menghabiskan seluruh barang SP yang belum dikirim sama sekali → SP ikut batal
--     lewat batalkan_sp (hanya peran alur jual; Vonny diarahkan ke sales/GM).
--   * Sesudah batal/pulih → finalisasi_kirim_sp (berkas 97): semua sisa 0 & ada ≥1 surat jalan →
--     no_surat_jalan terisi (batch terakhir), sisa > 0 lagi → dilepas.
-- Data: backfill qty_batal = qty untuk baris batal lama (turunan; DEV 0 baris). Tidak ada yang dihapus.

-- (1) Kolom ────────────────────────────────────────────────────────────────────
alter table public.sales_order_lines add column if not exists qty_batal numeric(14,2) not null default 0;
update public.sales_order_lines set qty_batal = qty where batal and qty_batal = 0;   -- turunan; pulih = set 0
alter table public.sales_order_lines drop constraint if exists sol_qty_batal_sah;
alter table public.sales_order_lines add constraint sol_qty_batal_sah check (qty_batal >= 0 and qty_batal <= qty);

-- (2) Trigger penjaga baris ────────────────────────────────────────────────────
create or replace function public.jaga_qty_batal_baris()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_kirim numeric; v_rpc boolean := coalesce(current_setting('rhj.batal_baris', true), '') = '1';
begin
  if tg_op = 'INSERT' then
    if not v_rpc and (coalesce(new.qty_batal, 0) <> 0 or coalesce(new.batal, false)) then
      raise exception 'Baris SP baru tidak bisa langsung berstatus batal.' using errcode='42501'; end if;
  else
    if not v_rpc and (new.qty_batal is distinct from old.qty_batal or new.batal is distinct from old.batal) then
      raise exception 'Pembatalan baris SP hanya lewat tombol Batalkan/Pulihkan (batalkan_baris_sp / pulihkan_baris_sp).'
        using errcode='42501'; end if;
    if not v_rpc and new.qty is distinct from old.qty and old.qty_batal > 0 then
      raise exception 'Baris ini punya pembatalan % — pulihkan dulu sebelum qty-nya diubah.', old.qty_batal
        using errcode='23514'; end if;
    if new.qty is distinct from old.qty or new.qty_batal is distinct from old.qty_batal then
      select coalesce(sum(kb.qty), 0) into v_kirim from public.so_kirim_baris kb where kb.so_line_id = new.id;
      if new.qty - new.qty_batal < v_kirim then
        raise exception 'Qty efektif baris (%) tidak boleh lebih kecil dari yang sudah terkirim (%).',
          new.qty - new.qty_batal, v_kirim using errcode='23514'; end if;
    end if;
  end if;
  new.batal := (new.qty_batal > 0 and new.qty_batal >= new.qty);   -- penanda lama = batal penuh
  return new;
end $function$;

drop trigger if exists sol_qty_batal on public.sales_order_lines;
create trigger sol_qty_batal before insert or update on public.sales_order_lines
  for each row execute function public.jaga_qty_batal_baris();

create or replace function public.jaga_hapus_baris_sp()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if not exists (select 1 from public.sales_orders s where s.id = old.so_id) then return old; end if; -- cascade hapus SP
  if exists (select 1 from public.so_kirim_baris kb where kb.so_line_id = old.id) then
    raise exception 'Baris ini sudah tercantum di surat jalan — tidak bisa dihapus/diganti. Batalkan surat jalannya dulu.'
      using errcode='23514'; end if;
  if old.qty_batal > 0 then
    raise exception 'Baris ini punya pembatalan % (%). Pulihkan dulu sebelum baris SP diganti, supaya catatan batalnya tidak hilang diam-diam.',
      old.qty_batal, coalesce(old.batal_alasan, '-') using errcode='23514'; end if;
  return old;
end $function$;

drop trigger if exists sol_jaga_hapus on public.sales_order_lines;
create trigger sol_jaga_hapus before delete on public.sales_order_lines
  for each row execute function public.jaga_hapus_baris_sp();

-- Cek Vonny gugur juga bila qty_batal berubah (oleh sales, sebelum barang keluar — perilaku berkas 88).
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
     and (new.product_id, new.qty, new.harga_nett, new.ehc_item, new.jenis, new.deskripsi, new.batal, new.qty_batal)
         is not distinct from
         (old.product_id, old.qty, old.harga_nett, old.ehc_item, old.jenis, old.deskripsi, old.batal, old.qty_batal) then
    return null;   -- kolom yang tidak dilihat Vonny (mis. urut, harga_list)
  end if;
  if tg_op <> 'DELETE' then perform public.gugurkan_cek_vonny(new.so_id); end if;
  if tg_op <> 'INSERT' and (tg_op = 'DELETE' or new.so_id is distinct from old.so_id) then
    perform public.gugurkan_cek_vonny(old.so_id);
  end if;
  return null;
end $function$;

-- Surat jalan bertahap tidak boleh melebihi qty EFEKTIF (berkas 89 membandingkan qty mentah).
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
  if v_kirim + new.qty > l.qty - l.qty_batal then   -- #18 berkas 98: qty efektif
    raise exception 'Qty kirim baris #% (%) melebihi sisa (%).', new.so_line_id, new.qty, l.qty - l.qty_batal - v_kirim
      using errcode = '23514';
  end if;
  return new;
end $function$;

-- (3) so_baris_hitung: qty EFEKTIF (kolom lama tetap; qty_pesan & qty_batal di ujung) ─────────────
create or replace view public.so_baris_hitung with (security_invoker = on) as
 SELECT l.id,
    l.so_id,
    l.urut,
    l.product_id,
    ((l.qty - l.qty_batal))::numeric(14,2) AS qty,
    l.harga_nett,
    l.ehc_item,
    COALESCE(l.harga_list, harga_berlaku(l.product_id)) AS harga_list,
    round(((l.qty - l.qty_batal) * l.harga_nett)) AS nilai_barang,
    round(((l.qty - l.qty_batal) * l.ehc_item)) AS nilai_ehc,
    round(((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item))) AS nilai_baris,
    (upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text) AS hammer,
        CASE
            WHEN (l.jenis = 'biaya'::text) THEN NULL::numeric
            WHEN (rep.komisi_flat_pct IS NOT NULL) THEN rep.komisi_flat_pct
            WHEN (hk.id IS NOT NULL) THEN hk.komisi_pct
            WHEN (s.cash_ok IS TRUE) THEN komisi_tier_cash(l.harga_nett, COALESCE(l.harga_list, harga_berlaku(l.product_id)))
            ELSE komisi_tier(l.harga_nett, COALESCE(l.harga_list, harga_berlaku(l.product_id)), (upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text))
        END AS pct,
    l.jenis,
    hk.id AS harga_khusus_id,
    l.qty AS qty_pesan,
    l.qty_batal
   FROM ((((sales_order_lines l
     LEFT JOIN products p ON ((p.id = l.product_id)))
     LEFT JOIN sales_orders s ON ((s.id = l.so_id)))
     LEFT JOIN sales_reps rep ON ((rep.id = s.sales_rep_id)))
     LEFT JOIN LATERAL ( SELECT h.id,
            h.komisi_pct
           FROM harga_khusus h
          WHERE ((h.status = 'aktif'::text) AND (h.customer_id = s.customer_id) AND (h.product_id = l.product_id) AND (l.harga_nett >= h.harga_nett))
         LIMIT 1) hk ON ((l.jenis <> 'biaya'::text)))
  WHERE (COALESCE(l.batal, false) = false) AND ((l.qty - l.qty_batal) > (0)::numeric);

-- (4) so_kirim_sisa: sisa = qty − qty_batal − terkirim ────────────────────────
create or replace view public.so_kirim_sisa with (security_invoker = on) as
 SELECT l.id AS so_line_id,
    l.so_id,
    l.qty AS qty_pesan,
    COALESCE(( SELECT sum(kb.qty) AS sum
           FROM so_kirim_baris kb
          WHERE (kb.so_line_id = l.id)), (0)::numeric) AS qty_kirim,
    ((l.qty - l.qty_batal) - COALESCE(( SELECT sum(kb.qty) AS sum
           FROM so_kirim_baris kb
          WHERE (kb.so_line_id = l.id)), (0)::numeric)) AS sisa,
    l.qty_batal,
    (l.qty - l.qty_batal) AS qty_efektif
   FROM sales_order_lines l
  WHERE ((NOT COALESCE(l.batal, false)) AND (l.jenis <> 'biaya'::text));

-- (5) Nilai awal & efektif per SP dan per PO ─────────────────────────────────
-- Rumus IDENTIK so_ringkas (efektif) & periksa_total_sp (awal). Kalau rumus itu berubah (#12), ubah bersama.
create or replace view public.sp_nilai_batal with (security_invoker = on) as
select x.*, x.grand_total_awal - x.grand_total_efektif as nilai_batal from (
  select s.id as so_id, s.po_id, s.no_sp, s.batal as sp_batal,
    coalesce(sum(round(l.qty * (l.harga_nett + l.ehc_item))), 0)
      + case when s.ppn_kena then round(coalesce(sum(round(l.qty * (l.harga_nett + l.ehc_item)))
                                                  filter (where l.jenis = 'barang'), 0) * 0.11) else 0 end
      as grand_total_awal,
    coalesce(sum(round((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item)))
               filter (where not l.batal and l.qty - l.qty_batal > 0), 0)
      + case when s.ppn_kena then round(coalesce(sum(round((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item)))
                                                  filter (where l.jenis = 'barang' and not l.batal and l.qty - l.qty_batal > 0), 0) * 0.11) else 0 end
      as grand_total_efektif,
    coalesce(sum(l.qty_batal), 0) as qty_batal_total,
    coalesce(bool_or(l.qty_batal > 0), false) as ada_batal
  from public.sales_orders s
  join public.sales_order_lines l on l.so_id = s.id
  group by s.id, s.po_id, s.no_sp, s.batal, s.ppn_kena) x;

create or replace view public.po_batal_ringkas with (security_invoker = on) as
select n.po_id,
       count(*) as jml_sp,
       sum(n.nilai_batal) as nilai_batal,
       max(p.grand_total) as grand_total_po,
       max(p.grand_total) - sum(n.nilai_batal) as grand_total_efektif,
       bool_or(n.ada_batal) as batal_sebagian
  from public.sp_nilai_batal n
  join public.po_ringkas p on p.po_id = n.po_id
 where n.po_id is not null and not n.sp_batal
 group by n.po_id;

-- sp_beda_po: bandingkan nilai AWAL (sama dengan periksa_total_sp) — alarm palsu sesudah batal hilang.
create or replace view public.sp_beda_po with (security_invoker = on) as
 SELECT s.id AS so_id,
    s.no_sp,
    s.tanggal,
    s.kepada,
    s.sales_rep_id,
    p.no_po,
    COALESCE(n.grand_total_awal, (0)::numeric) AS total_sp,
    COALESCE(p.grand_total, (0)::numeric) AS total_po,
    (COALESCE(n.grand_total_awal, (0)::numeric) - COALESCE(p.grand_total, (0)::numeric)) AS selisih,
    COALESCE(r.grand_total, (0)::numeric) AS total_sp_efektif
   FROM (((sales_orders s
     JOIN po_ringkas p ON ((p.po_id = s.po_id)))
     LEFT JOIN so_ringkas r ON ((r.so_id = s.id)))
     LEFT JOIN sp_nilai_batal n ON ((n.so_id = s.id)))
  WHERE ((NOT s.batal) AND (EXISTS ( SELECT 1
           FROM sales_order_lines l
          WHERE (l.so_id = s.id))) AND (COALESCE(n.grand_total_awal, (0)::numeric) <> COALESCE(p.grand_total, (0)::numeric)));

create or replace function public.sp_selisih_po(p_so bigint)
 returns numeric
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
           when s.po_id is null then null
           when p.po_id is null then null
           else coalesce(n.grand_total_awal, 0) - coalesce(p.grand_total, 0)   -- #18: nilai awal, = periksa_total_sp
         end
    from public.sales_orders s
    left join public.sp_nilai_batal n on n.so_id = s.id
    left join public.po_ringkas p on p.po_id = s.po_id
   where s.id = p_so and public.boleh_lihat_sp(p_so)
$function$;

-- (6) batalkan_baris_sp(p_line, p_alasan, p_qty opsional) ──────────────────────
-- Overload lama di-DROP: dua kandidat membuat PostgREST gagal memilih. Panggilan lama {p_line,p_alasan}
-- tetap jalan dan membatalkan seluruh SISA (bukan yang sudah terkirim).
drop function if exists public.batalkan_baris_sp(bigint, text);
create or replace function public.batalkan_baris_sp(p_line bigint, p_alasan text, p_qty numeric default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_so bigint; l record; s record; v_kirim numeric; v_sisa numeric; v_q numeric; v_fin text; v_catat text;
begin
  if not (public.boleh_alur_jual() or public.peran_saya() = 'vonny') then
    raise exception 'Anda tidak berhak membatalkan baris Surat Pesanan.' using errcode='42501'; end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Pembatalan wajib beralasan.' using errcode='22023'; end if;
  select so_id into v_so from public.sales_order_lines where id = p_line;
  if v_so is null then raise exception 'Baris tidak ditemukan.' using errcode='P0002'; end if;
  -- urutan kunci: SP lalu baris (sama dengan tambah_surat_jalan)
  select * into s from public.sales_orders where id = v_so for update;
  select * into l from public.sales_order_lines where id = p_line for update;
  if not (public.setara_owner() or public.peran_saya() in ('staff','vonny')
          or s.sales_rep_id = public.sales_rep_saya()) then
    raise exception 'Surat Pesanan % milik sales lain.', s.no_sp using errcode='42501'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode='23514'; end if;
  if s.no_invoice is not null then
    raise exception 'Invoice Surat Pesanan % sudah terbit — pembatalan lewat retur, bukan di sini.', s.no_sp
      using errcode='23514'; end if;
  if s.no_surat_jalan is not null then
    raise exception 'Surat Pesanan % sudah terkirim semua (surat jalan %) — tidak ada sisa yang bisa dibatalkan; lewat retur.',
      s.no_sp, s.no_surat_jalan using errcode='23514'; end if;
  if exists (select 1 from public.ehc_klaim k where k.so_id = s.id)
     or exists (select 1 from public.komisi_klaim k where k.so_id = s.id) then
    raise exception 'Klaim EHC/komisi Surat Pesanan % sudah diajukan — batalkan klaimnya dulu.', s.no_sp
      using errcode='23514'; end if;
  if l.jenis = 'biaya' then
    if coalesce(l.batal, false) then return 'Baris sudah dibatalkan.'; end if;
    v_kirim := 0;
  else
    select coalesce(sum(kb.qty), 0) into v_kirim from public.so_kirim_baris kb where kb.so_line_id = p_line;
  end if;
  v_sisa := l.qty - l.qty_batal - v_kirim;
  if v_sisa <= 0 then
    raise exception 'Tidak ada sisa yang bisa dibatalkan (pesan %, terkirim %, sudah batal %).',
      l.qty, v_kirim, l.qty_batal using errcode='23514'; end if;
  v_q := coalesce(p_qty, v_sisa);
  if v_q <= 0 then raise exception 'Qty batal harus lebih dari 0.' using errcode='22023'; end if;
  if v_q > v_sisa then
    raise exception 'Qty batal (%) melebihi sisa yang belum terkirim (%). Qty yang sudah terkirim (%) tidak bisa dibatalkan — lewat retur.',
      v_q, v_sisa, v_kirim using errcode='23514'; end if;

  -- Seluruh barang SP habis dibatalkan (pasti belum ada yang terkirim) → SP ikut batal lewat batalkan_sp.
  if not exists (select 1 from public.sales_order_lines x
                  where x.so_id = v_so and x.jenis = 'barang'
                    and x.qty - x.qty_batal - case when x.id = p_line then v_q else 0 end > 0) then
    if not public.boleh_alur_jual() then
      raise exception 'Pembatalan ini menghabiskan seluruh barang Surat Pesanan % — artinya SP-nya batal. '
                      'Minta sales pemegang, staff, atau GM menekan "Batalkan SP".', s.no_sp using errcode='42501'; end if;
    perform public.batalkan_sp(v_so, 'Semua barang dibatalkan: ' || btrim(p_alasan));
    return 'Semua barang Surat Pesanan ' || s.no_sp || ' dibatalkan — SP ikut dibatalkan.';
  end if;

  v_catat := to_char(now() at time zone 'Asia/Jakarta', 'DD/MM/YYYY') || ' batal ' || v_q::text || ': ' || btrim(p_alasan);
  perform set_config('rhj.usul', 'on', true);
  perform set_config('rhj.batal_baris', '1', true);
  update public.sales_order_lines
     set qty_batal    = qty_batal + v_q,
         batal_alasan = case when batal_alasan is null then v_catat else batal_alasan || E'\n' || v_catat end,
         batal_oleh   = auth.uid(),
         batal_pada   = now()
   where id = p_line;
  perform set_config('rhj.batal_baris', '', true);
  perform set_config('rhj.usul', '', true);

  v_fin := public.finalisasi_kirim_sp(v_so);   -- (e): semua sisa 0 & ada surat jalan → no_surat_jalan terisi
  return 'Qty ' || v_q::text || ' dibatalkan.' ||
         case when v_fin = 'lengkap'
              then ' Semua sisa sudah terkirim/dibatalkan — surat jalan terakhir menjadi penyelesai, invoice boleh diterbitkan.'
              else ' Nilai SP, komisi, dan EHC menyesuaikan.' end;
end $function$;

-- (7) pulihkan_baris_sp(p_line, p_qty opsional) ──────────────────────────────
drop function if exists public.pulihkan_baris_sp(bigint);
create or replace function public.pulihkan_baris_sp(p_line bigint, p_qty numeric default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_so bigint; l record; s record; v_q numeric; v_fin text; v_catat text;
begin
  if not (public.boleh_alur_jual() or public.peran_saya() = 'vonny') then
    raise exception 'Anda tidak berhak memulihkan baris Surat Pesanan.' using errcode='42501'; end if;
  select so_id into v_so from public.sales_order_lines where id = p_line;
  if v_so is null then raise exception 'Baris tidak ditemukan.' using errcode='P0002'; end if;
  select * into s from public.sales_orders where id = v_so for update;
  select * into l from public.sales_order_lines where id = p_line for update;
  if not (public.setara_owner() or public.peran_saya() in ('staff','vonny')
          or s.sales_rep_id = public.sales_rep_saya()) then
    raise exception 'Surat Pesanan % milik sales lain.', s.no_sp using errcode='42501'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode='23514'; end if;
  if s.no_invoice is not null then
    raise exception 'Invoice Surat Pesanan % sudah terbit — baris tidak bisa dipulihkan.', s.no_sp using errcode='23514'; end if;
  if s.no_surat_jalan is not null and not exists (select 1 from public.so_kirim k where k.so_id = v_so) then
    raise exception 'Surat Pesanan % sudah dikirim sekaligus (surat jalan %) — baris tidak bisa dipulihkan.',
      s.no_sp, s.no_surat_jalan using errcode='23514'; end if;
  if exists (select 1 from public.ehc_klaim k where k.so_id = s.id)
     or exists (select 1 from public.komisi_klaim k where k.so_id = s.id) then
    raise exception 'Klaim EHC/komisi Surat Pesanan % sudah diajukan — batalkan klaimnya dulu.', s.no_sp
      using errcode='23514'; end if;
  if l.qty_batal <= 0 then return 'Baris tidak dalam keadaan batal.'; end if;
  v_q := coalesce(p_qty, l.qty_batal);
  if v_q <= 0 then raise exception 'Qty pulih harus lebih dari 0.' using errcode='22023'; end if;
  if v_q > l.qty_batal then
    raise exception 'Qty pulih (%) melebihi qty yang dibatalkan (%).', v_q, l.qty_batal using errcode='23514'; end if;

  v_catat := to_char(now() at time zone 'Asia/Jakarta', 'DD/MM/YYYY') || ' pulih ' || v_q::text;
  perform set_config('rhj.usul', 'on', true);
  perform set_config('rhj.batal_baris', '1', true);
  if v_q = l.qty_batal then
    update public.sales_order_lines
       set qty_batal = 0, batal_alasan = null, batal_oleh = null, batal_pada = null
     where id = p_line;
  else
    update public.sales_order_lines
       set qty_batal = qty_batal - v_q,
           batal_alasan = case when batal_alasan is null then v_catat else batal_alasan || E'\n' || v_catat end
     where id = p_line;
  end if;
  perform set_config('rhj.batal_baris', '', true);
  perform set_config('rhj.usul', '', true);

  v_fin := public.finalisasi_kirim_sp(v_so);
  return 'Qty ' || v_q::text || ' dipulihkan ke SP.' ||
         case when v_fin = 'dibuka'
              then ' Surat jalan penyelesai dilepas — sisa perlu dikirim lagi sebelum invoice.'
              else '' end;
end $function$;

-- (8) Laporan memakai qty efektif ───────────────────────────────────────────
create or replace function public.laporan_margin_produk(p_dari date default null::date, p_sampai date default null::date)
 returns table(kode text, brand text, jumlah_sp bigint, qty numeric, nilai_jual numeric, nilai_hpp numeric, margin_rp numeric, margin_pct numeric, nilai_ehc numeric, qty_tanpa_hpp numeric)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not public.boleh_laporan_margin() then
    raise exception 'Laporan margin hanya untuk owner, GM, dan finance — '
                    'orang yang sama yang boleh menetapkan HPP.' using errcode = '42501';
  end if;

  return query
  with baris as (
    select l.product_id,
           (l.qty - l.qty_batal)                                        as qty,   -- #18: qty efektif
           round((l.qty - l.qty_batal) * coalesce(l.harga_nett, 0))     as jual,
           round((l.qty - l.qty_batal) * coalesce(l.ehc_item, 0))       as ehc,
           -- HPP yang berlaku SAAT SP DIBUAT, bukan hari ini.
           public.hpp_berlaku(l.product_id, s.tanggal)                  as hpp_satuan,
           s.id                                                         as so_id
      from public.sales_orders s
      join public.sales_order_lines l on l.so_id = s.id
     where not s.batal
       and not l.batal
       and l.qty - l.qty_batal > 0
       and l.jenis <> 'biaya'
       and l.product_id is not null
       and (p_dari   is null or s.tanggal >= p_dari)
       and (p_sampai is null or s.tanggal <= p_sampai)
  )
  select coalesce(p.kode, '(tanpa kode)')::text                   as kode,
         coalesce(p.brand, '')::text                              as brand,
         count(distinct b.so_id)                                  as jumlah_sp,
         sum(b.qty)                                               as qty,
         sum(b.jual)                                              as nilai_jual,
         -- Baris tanpa HPP TIDAK ikut dijumlahkan.
         sum(case when b.hpp_satuan is null then 0
                  else round(b.qty * b.hpp_satuan) end)           as nilai_hpp,
         sum(case when b.hpp_satuan is null then 0
                  else b.jual - round(b.qty * b.hpp_satuan) end)  as margin_rp,
         -- Persentase dihitung hanya atas bagian yang HPP-nya diketahui.
         case when sum(case when b.hpp_satuan is null then 0 else b.jual end) = 0 then null
              else round(
                100.0 * sum(case when b.hpp_satuan is null then 0
                                 else b.jual - round(b.qty * b.hpp_satuan) end)
                      / sum(case when b.hpp_satuan is null then 0 else b.jual end), 1)
         end                                                      as margin_pct,
         sum(b.ehc)                                               as nilai_ehc,
         sum(case when b.hpp_satuan is null then b.qty else 0 end) as qty_tanpa_hpp
    from baris b
    left join public.products p on p.id = b.product_id
   group by 1, 2
   order by 7 desc nulls last;
end $function$;

create or replace function public.laporan_margin_sp(p_dari date default null::date, p_sampai date default null::date)
 returns table(no_sp text, tanggal date, kepada text, sales text, status text, nilai_jual numeric, nilai_hpp numeric, margin_rp numeric, margin_pct numeric, nilai_ehc numeric, baris_tanpa_hpp bigint)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not public.boleh_laporan_margin() then
    raise exception 'Laporan margin hanya untuk owner, GM, dan finance — '
                    'orang yang sama yang boleh menetapkan HPP.' using errcode = '42501';
  end if;

  return query
  with baris as (
    select s.id                                                  as so_id,
           s.no_sp, s.tanggal, s.kepada, s.status, s.sales_rep_id,
           round((l.qty - l.qty_batal) * coalesce(l.harga_nett, 0)) as jual,   -- #18: qty efektif
           round((l.qty - l.qty_batal) * coalesce(l.ehc_item, 0))   as ehc,
           public.hpp_berlaku(l.product_id, s.tanggal)           as hpp_satuan,
           (l.qty - l.qty_batal)                                 as qty
      from public.sales_orders s
      join public.sales_order_lines l on l.so_id = s.id
     where not s.batal
       and not l.batal
       and l.qty - l.qty_batal > 0
       and l.jenis <> 'biaya'
       and l.product_id is not null
       and (p_dari   is null or s.tanggal >= p_dari)
       and (p_sampai is null or s.tanggal <= p_sampai)
  )
  select b.no_sp,
         b.tanggal,
         b.kepada,
         coalesce(r.nama, '—')::text                              as sales,
         b.status,
         sum(b.jual)                                              as nilai_jual,
         sum(case when b.hpp_satuan is null then 0
                  else round(b.qty * b.hpp_satuan) end)           as nilai_hpp,
         sum(case when b.hpp_satuan is null then 0
                  else b.jual - round(b.qty * b.hpp_satuan) end)  as margin_rp,
         case when sum(case when b.hpp_satuan is null then 0 else b.jual end) = 0 then null
              else round(
                100.0 * sum(case when b.hpp_satuan is null then 0
                                 else b.jual - round(b.qty * b.hpp_satuan) end)
                      / sum(case when b.hpp_satuan is null then 0 else b.jual end), 1)
         end                                                      as margin_pct,
         sum(b.ehc)                                               as nilai_ehc,
         count(*) filter (where b.hpp_satuan is null)             as baris_tanpa_hpp
    from baris b
    left join public.sales_reps r on r.id = b.sales_rep_id
   group by b.no_sp, b.tanggal, b.kepada, r.nama, b.status
   order by 9 nulls last, 8;
end $function$;

create or replace function public.gm_konteks_keputusan(p_jenis text, p_ref bigint)
 returns table(kode text, qty numeric, harga_nett numeric, ehc numeric, hpp numeric, margin numeric)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh melihat konteks HPP keputusan.' using errcode='42501';
  end if;
  if p_jenis in ('harga','telat') then
    return query
      select coalesce(p.kode,'-'), l.qty - l.qty_batal, l.harga_nett, l.ehc_item,   -- #18: qty efektif
             public.hpp_berlaku(l.product_id, s.tanggal),
             (l.harga_nett - coalesce(public.hpp_berlaku(l.product_id, s.tanggal),0))
      from public.sales_order_lines l
      join public.sales_orders s on s.id = l.so_id
      left join public.products p on p.id = l.product_id
      where l.so_id = p_ref and l.jenis = 'barang' and not l.batal and l.qty - l.qty_batal > 0
      order by l.urut;
  elsif p_jenis = 'harga_khusus' then
    return query
      select coalesce(p.kode,'-'), null::numeric, h.harga_nett, h.ehc_item,
             public.hpp_berlaku(h.product_id, coalesce((select s2.tanggal from public.sales_orders s2 where s2.id = h.so_id), current_date)),
             (h.harga_nett - coalesce(public.hpp_berlaku(h.product_id, coalesce((select s2.tanggal from public.sales_orders s2 where s2.id = h.so_id), current_date)),0))
      from public.harga_khusus h
      left join public.products p on p.id = h.product_id
      where h.id = p_ref;
  end if;
end $function$;

-- (9) Grant ──────────────────────────────────────────────────────────────────
revoke all on function public.batalkan_baris_sp(bigint,text,numeric), public.pulihkan_baris_sp(bigint,numeric) from public, anon;
grant execute on function public.batalkan_baris_sp(bigint,text,numeric), public.pulihkan_baris_sp(bigint,numeric) to authenticated;
revoke execute on function public.jaga_qty_batal_baris(), public.jaga_hapus_baris_sp(),
                           public.sp_vonny_gugur_baris(), public.jaga_so_kirim_baris() from public, anon;
revoke all on public.sp_nilai_batal, public.po_batal_ringkas from anon;
revoke insert, update, delete, truncate, references, trigger
  on public.sp_nilai_batal, public.po_batal_ringkas, public.so_baris_hitung, public.sp_beda_po, public.so_kirim_sisa from authenticated;
grant select on public.sp_nilai_batal, public.po_batal_ringkas to authenticated;

notify pgrst, 'reload schema';
