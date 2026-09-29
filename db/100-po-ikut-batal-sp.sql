-- Berkas 100 (#18, lanjutan berkas 98): SP yang habis dibatalkan lewat pembatalan barang → PO ikut
--   mencerminkan pembatalan, dan tidak kembali ke antrean "PO belum dibuatkan SP".
--
-- Temuan (review, diverifikasi di DEV begin…rollback sebagai GM): batalkan_baris_sp yang menghabiskan
--   seluruh barang SP memanggil batalkan_sp → SP batal. Tetapi:
--     * po_batal_ringkas membuang SP batal (where not n.sp_batal) → PO tampak utuh, tanpa label/nilai batal;
--     * po_belum_sp hanya melihat SP tidak batal → PO masuk lagi ke antrean "belum dibuatkan SP", tim
--       terdorong membuat SP baru untuk pesanan yang sudah dibatalkan customer;
--     * purchase_orders.batal tetap false.
--
-- Keputusan desain:
--   * Penanda aditif sales_orders.batal_karena_barang (default false) — membedakan "SP batal karena customer
--     membatalkan barangnya" (#18) dari batalkan_sp biasa (mis. SP salah input yang akan dibuat ulang: PO
--     SENGAJA kembali ke antrean).
--   * batalkan_baris_sp jalur "semua barang habis": sesudah batalkan_sp, tandai batal_karena_barang; bila PO
--     tidak punya SP lain yang masih berlaku → PO ikut ditandai batal (flag, alasan sama, bisa ditelusuri —
--     tidak ada data yang dihapus). PO dengan SP lain yang masih berlaku TIDAK dibatalkan; nilainya tampil
--     sebagai batal di po_batal_ringkas.
--   * po_batal_ringkas: SP batal_karena_barang ikut dihitung (nilai_batal = nilai awal SP, efektif 0).
--     Kolom baru di akhir: batal_semua (semua SP terkait habis dibatalkan barangnya).
--   * po_belum_sp: PO yang SP-nya dibatalkan lewat pembatalan barang tidak masuk antrean (lapis kedua,
--     meski PO-nya belum ditandai batal).
--   * Invariant SP = PO (periksa_total_sp / sp_beda_po) tidak berubah: tetap membandingkan nilai AWAL.
--     sp_beda_po hanya melihat SP tidak batal, jadi SP batal tidak memicu alarm.
-- Data: tidak ada baris yang diubah (DEV: 0 SP batal lewat baris).

alter table public.sales_orders
  add column if not exists batal_karena_barang boolean not null default false;
comment on column public.sales_orders.batal_karena_barang is
  '#18 berkas 100: SP batal karena seluruh barangnya dibatalkan customer (batalkan_baris_sp), bukan batalkan_sp biasa.';

-- ── batalkan_baris_sp: identik dengan berkas 98, kecuali jalur "semua barang habis" ─────────────────
create or replace function public.batalkan_baris_sp(p_line bigint, p_alasan text, p_qty numeric default null)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_so bigint; l record; s record; v_kirim numeric; v_sisa numeric; v_q numeric; v_fin text; v_catat text;
        v_po record; v_po_batal boolean := false;
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
    -- #18 berkas 100: penanda SP batal karena barang → PO mencerminkan pembatalan, tidak kembali ke antrean.
    update public.sales_orders set batal_karena_barang = true where id = v_so;
    if s.po_id is not null then
      select * into v_po from public.purchase_orders where id = s.po_id for update;
      if v_po.id is not null and not v_po.batal
         and not exists (select 1 from public.sales_orders o where o.po_id = s.po_id and not o.batal) then
        update public.purchase_orders
           set batal = true,
               alasan_batal = 'Semua barang dibatalkan customer (SP ' || s.no_sp || '): ' || btrim(p_alasan),
               dibatalkan_pada = now(), dibatalkan_oleh = auth.uid(),
               diubah_pada = now(), diubah_oleh = auth.uid()
         where id = s.po_id;
        v_po_batal := true;
      end if;
    end if;
    return 'Semua barang Surat Pesanan ' || s.no_sp || ' dibatalkan — SP ikut dibatalkan'
           || case when v_po_batal then ', PO ' || v_po.no_po || ' ikut ditandai batal.'
                   when s.po_id is not null then '; PO masih punya SP lain yang berlaku — nilai SP ini tampil sebagai batal di PO.'
                   else '.' end;
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
revoke all on function public.batalkan_baris_sp(bigint, text, numeric) from public, anon;
grant execute on function public.batalkan_baris_sp(bigint, text, numeric) to authenticated;

-- ── po_batal_ringkas: SP yang batal karena barang ikut dihitung (nilai batal = nilai awal) ───────────
create or replace view public.po_batal_ringkas with (security_invoker = on) as
select n.po_id,
       count(*) as jml_sp,
       sum(case when n.sp_batal then n.grand_total_awal else n.nilai_batal end) as nilai_batal,
       max(p.grand_total) as grand_total_po,
       max(p.grand_total) - sum(case when n.sp_batal then n.grand_total_awal else n.nilai_batal end) as grand_total_efektif,
       bool_or(n.ada_batal or n.sp_batal) as batal_sebagian,
       bool_and(n.sp_batal) as batal_semua
  from public.sp_nilai_batal n
  join public.sales_orders s on s.id = n.so_id
  join public.po_ringkas p on p.po_id = n.po_id
 where n.po_id is not null and (not n.sp_batal or s.batal_karena_barang)
 group by n.po_id;

-- ── po_belum_sp: PO yang SP-nya habis dibatalkan barangnya bukan pekerjaan "buat SP" ────────────────
create or replace view public.po_belum_sp with (security_invoker = on) as
select p.id as po_id, p.no_po, p.tanggal, p.customer_id, p.nama_customer, p.sales_rep_id, p.ppn_kena
  from public.purchase_orders p
 where not p.batal
   and not exists (select 1 from public.sales_orders s where s.po_id = p.id and not s.batal)
   and not exists (select 1 from public.sales_orders s where s.po_id = p.id and s.batal_karena_barang);

revoke all on public.po_batal_ringkas from anon;
grant select on public.po_batal_ringkas to authenticated;
