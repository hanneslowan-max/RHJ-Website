-- Berkas 106 (#12): rupiah BERSEN, TANPA pembulatan.
-- Keputusan Hannes: semua rupiah tampil "Rp 1.234,56" dan tidak ada pembulatan di mana pun
-- (PPN, komisi, total, laporan). Numeric Postgres eksak → view & fungsi menghitung presisi penuh
-- (mis. PPN = dasar × 0,11 tetap 4 desimal). Sen hanya muncul saat TAMPIL (2 desimal) dan saat
-- DISIMPAN ke kolom numeric(…,2).
-- "SP = PO" kini berarti SAMA SAMPAI SEN (presisi yang tercetak di dokumen):
--   round(sp, 2) <> round(po, 2) → tolak. round() HANYA di pembanding, tidak di nilai.
-- Dibiarkan (bukan pembulatan uang yang merusak): isi_nilai_* (round(x,2) = presisi kolom
-- numeric(18,2)), hitung_edit_massal (opsi pembulatan pilihan pengguna), round(…,1) margin_pct
-- (persen), trunc() di periksa_baris_po_usul / periksa_komposisi_set (validasi presisi input).
-- Kolom & urutan view identik (CREATE OR REPLACE); security_invoker=on WAJIB diulang
-- (tanpa klausa ini PG menghapus opsinya → RLS terlewati). Grant tetap.

-- (1) teks rupiah bersen, lepas dari lc_numeric (DEV en_US → G = koma)
create or replace function public.rp_teks(p numeric)
returns text language sql immutable parallel safe set search_path = public as $f$
  select case when p is null then null
         else 'Rp ' || translate(to_char(p, 'FM999,999,999,999,999,990.00'), ',.', '.,') end
$f$;
revoke execute on function public.rp_teks(numeric) from public, anon;
grant execute on function public.rp_teks(numeric) to authenticated;

-- (2) po_ringkas: nilai baris sekali di LATERAL, tanpa round per baris & tanpa round PPN
create or replace view public.po_ringkas with (security_invoker = on) as
select p.id as po_id, p.no_po, p.tanggal, p.nama_customer, p.sales_rep_id, p.ppn_kena,
       coalesce(sum(n.nilai), 0::numeric) as sub_total,
       case when p.ppn_kena then coalesce(sum(n.nilai) filter (where l.jenis = 'barang'), 0::numeric) * 0.11
            else 0::numeric end as ppn,
       coalesce(sum(n.nilai), 0::numeric)
       + case when p.ppn_kena then coalesce(sum(n.nilai) filter (where l.jenis = 'barang'), 0::numeric) * 0.11
              else 0::numeric end as grand_total,
       count(l.id) as jumlah_baris,
       coalesce(sum(n.nilai) filter (where l.jenis = 'barang'), 0::numeric) as dasar_ppn,
       coalesce(sum(n.nilai) filter (where l.jenis = 'barang'), 0::numeric) as total_barang,
       coalesce(sum(n.nilai) filter (where l.jenis = 'biaya'),  0::numeric) as total_biaya
  from public.purchase_orders p
  left join public.po_lines l on l.po_id = p.id
  left join lateral (
    select l.qty * l.harga
           - case when coalesce(l.diskon_tipe, 'rp') = 'persen'
                  then l.qty * l.harga * coalesce(l.diskon, 0::numeric) / 100::numeric
                  else coalesce(l.diskon, 0::numeric) end as nilai) n on true
 group by p.id;

-- (3) so_baris_hitung: definisi live (#18 qty efektif), 3 kolom nilai tanpa round
create or replace view public.so_baris_hitung with (security_invoker = on) as
select l.id, l.so_id, l.urut, l.product_id,
       (l.qty - l.qty_batal)::numeric(14,2) as qty,
       l.harga_nett, l.ehc_item,
       coalesce(l.harga_list, public.harga_berlaku(l.product_id)) as harga_list,
       (l.qty - l.qty_batal) * l.harga_nett as nilai_barang,
       (l.qty - l.qty_batal) * l.ehc_item as nilai_ehc,
       (l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item) as nilai_baris,
       upper(coalesce(p.brand, '')) = 'HAMMER' as hammer,
       case
         when l.jenis = 'biaya' then null::numeric
         when rep.komisi_flat_pct is not null then rep.komisi_flat_pct
         when hk.id is not null then hk.komisi_pct
         when s.cash_ok is true then public.komisi_tier_cash(l.harga_nett, coalesce(l.harga_list, public.harga_berlaku(l.product_id)))
         else public.komisi_tier(l.harga_nett, coalesce(l.harga_list, public.harga_berlaku(l.product_id)), upper(coalesce(p.brand, '')) = 'HAMMER')
       end as pct,
       l.jenis,
       hk.id as harga_khusus_id,
       l.qty as qty_pesan,
       l.qty_batal
  from public.sales_order_lines l
  left join public.products p on p.id = l.product_id
  left join public.sales_orders s on s.id = l.so_id
  left join public.sales_reps rep on rep.id = s.sales_rep_id
  left join lateral (
    select h.id, h.komisi_pct
      from public.harga_khusus h
     where h.status = 'aktif' and h.customer_id = s.customer_id and h.product_id = l.product_id
       and l.harga_nett >= h.harga_nett
     limit 1) hk on l.jenis <> 'biaya'
 where coalesce(l.batal, false) = false and (l.qty - l.qty_batal) > 0::numeric;

-- (4) so_ringkas: PPN & komisi tanpa round
create or replace view public.so_ringkas with (security_invoker = on) as
select s.id as so_id, s.no_sp, s.tanggal, s.sales_rep_id, s.ppn_kena, s.status,
       coalesce(sum(b.nilai_barang) filter (where b.jenis = 'barang'), 0::numeric) as total_barang,
       coalesce(sum(b.nilai_ehc), 0::numeric) as total_ehc,
       coalesce(sum(b.nilai_baris), 0::numeric) as sub_total,
       case when s.ppn_kena then coalesce(sum(b.nilai_baris) filter (where b.jenis = 'barang'), 0::numeric) * 0.11
            else 0::numeric end as ppn,
       coalesce(sum(b.nilai_baris), 0::numeric)
       + case when s.ppn_kena then coalesce(sum(b.nilai_baris) filter (where b.jenis = 'barang'), 0::numeric) * 0.11
              else 0::numeric end as grand_total,
       coalesce(sum(b.nilai_barang * b.pct) filter (where b.pct is not null), 0::numeric) as komisi,
       coalesce(bool_or(b.pct is null) filter (where b.id is not null and b.jenis = 'barang'), false) as ada_bawah_list,
       count(b.id) as jumlah_baris,
       coalesce(sum(b.nilai_barang) filter (where b.jenis = 'biaya'), 0::numeric) as total_biaya,
       coalesce(sum(b.nilai_baris) filter (where b.jenis = 'barang'), 0::numeric) as dasar_ppn
  from public.sales_orders s
  left join public.so_baris_hitung b on b.so_id = s.id
 group by s.id;

-- (5) cash_belum_cocok: komisi kalau cash tanpa round
create or replace view public.cash_belum_cocok with (security_invoker = on) as
select s.id as so_id, s.no_sp, s.tanggal, s.kepada, s.sales_rep_id, s.lunas, s.tgl_lunas, s.no_invoice,
       coalesce(r.total_barang, 0::numeric) as total_barang,
       coalesce(r.komisi, 0::numeric) as komisi_sekarang,
       (select coalesce(sum(b.nilai_barang * public.komisi_tier_cash(b.harga_nett, b.harga_list)), 0::numeric) as "coalesce"
          from public.so_baris_hitung b
         where b.so_id = s.id and b.jenis = 'barang' and b.harga_khusus_id is null
           and public.komisi_tier_cash(b.harga_nett, b.harga_list) is not null)
       + (select coalesce(sum(b.nilai_barang * b.pct), 0::numeric) as "coalesce"
            from public.so_baris_hitung b
           where b.so_id = s.id and b.jenis = 'barang' and b.harga_khusus_id is not null) as komisi_kalau_cash
  from public.sales_orders s
  left join public.so_ringkas r on r.so_id = s.id
 where s.cash_minta and s.cash_ok is null and not s.batal;

-- (6) sp_nilai_batal (#18): total awal & efektif tanpa round
create or replace view public.sp_nilai_batal with (security_invoker = on) as
select so_id, po_id, no_sp, sp_batal, grand_total_awal, grand_total_efektif, qty_batal_total, ada_batal,
       grand_total_awal - grand_total_efektif as nilai_batal
  from (select s.id as so_id, s.po_id, s.no_sp, s.batal as sp_batal,
               coalesce(sum(l.qty * (l.harga_nett + l.ehc_item)), 0::numeric)
               + case when s.ppn_kena
                      then coalesce(sum(l.qty * (l.harga_nett + l.ehc_item)) filter (where l.jenis = 'barang'), 0::numeric) * 0.11
                      else 0::numeric end as grand_total_awal,
               coalesce(sum((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item))
                          filter (where not l.batal and (l.qty - l.qty_batal) > 0::numeric), 0::numeric)
               + case when s.ppn_kena
                      then coalesce(sum((l.qty - l.qty_batal) * (l.harga_nett + l.ehc_item))
                                      filter (where l.jenis = 'barang' and not l.batal and (l.qty - l.qty_batal) > 0::numeric), 0::numeric) * 0.11
                      else 0::numeric end as grand_total_efektif,
               coalesce(sum(l.qty_batal), 0::numeric) as qty_batal_total,
               coalesce(bool_or(l.qty_batal > 0::numeric), false) as ada_batal
          from public.sales_orders s
          join public.sales_order_lines l on l.so_id = s.id
         group by s.id, s.po_id, s.no_sp, s.batal, s.ppn_kena) x;

-- (7) sp_beda_po: kolom sama; beda dihitung sampai sen
create or replace view public.sp_beda_po with (security_invoker = on) as
select s.id as so_id, s.no_sp, s.tanggal, s.kepada, s.sales_rep_id, p.no_po,
       coalesce(n.grand_total_awal, 0::numeric) as total_sp,
       coalesce(p.grand_total, 0::numeric) as total_po,
       coalesce(n.grand_total_awal, 0::numeric) - coalesce(p.grand_total, 0::numeric) as selisih,
       coalesce(r.grand_total, 0::numeric) as total_sp_efektif
  from public.sales_orders s
  join public.po_ringkas p on p.po_id = s.po_id
  left join public.so_ringkas r on r.so_id = s.id
  left join public.sp_nilai_batal n on n.so_id = s.id
 where not s.batal
   and exists (select 1 from public.sales_order_lines l where l.so_id = s.id)
   and round(coalesce(n.grand_total_awal, 0::numeric), 2) <> round(coalesce(p.grand_total, 0::numeric), 2);

-- (8) periksa_total_sp: rumus tanpa round, pembanding sampai sen, pesan Rp bersen
create or replace function public.periksa_total_sp(p_so bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_no_sp text; v_no_po text; v_po bigint; v_baris bigint;
  v_ppn boolean; v_sp_total numeric; v_po_total numeric;
begin
  select s.po_id, s.no_sp, s.ppn_kena into v_po, v_no_sp, v_ppn
    from public.sales_orders s where s.id = p_so;
  if v_po is null then return; end if;

  select count(*) into v_baris from public.sales_order_lines where so_id = p_so;
  if v_baris = 0 then return; end if;

  -- #18: SEMUA baris (termasuk batal). #12: rumus identik sp_nilai_batal.grand_total_awal,
  -- TANPA pembulatan: sum(qty*(nett+ehc)) + PPN (sum 'barang' * 0.11).
  select
    coalesce(sum(l.qty * (l.harga_nett + l.ehc_item)), 0)
    + case when v_ppn
        then coalesce(sum(l.qty * (l.harga_nett + l.ehc_item)) filter (where l.jenis = 'barang'), 0) * 0.11
        else 0 end
  into v_sp_total
  from public.sales_order_lines l
  where l.so_id = p_so;

  select p.grand_total, p.no_po into v_po_total, v_no_po
    from public.po_ringkas p where p.po_id = v_po;
  if v_po_total is null then return; end if;

  -- #12: sama SAMPAI SEN (presisi yang tercetak di dokumen)
  if round(coalesce(v_sp_total, 0), 2) <> round(v_po_total, 2) then
    raise exception
      'Grand total Surat Pesanan % adalah %, sedangkan PO % adalah % — selisih %. '
      'Harga nett + EHC per baris harus menjumlah persis ke angka PO. '
      'Kalau justru PO-nya yang salah, perbaiki PO-nya dulu, jangan SP-nya.',
      coalesce(v_no_sp, '(baru)'),
      public.rp_teks(coalesce(v_sp_total, 0)),
      coalesce(v_no_po, '(?)'),
      public.rp_teks(v_po_total),
      public.rp_teks(abs(coalesce(v_sp_total, 0) - v_po_total));
  end if;
end $function$;

-- (9) komisi_hitung: komisi SP telat = total_barang × gm_pct (tanpa round)
create or replace function public.komisi_hitung(p_so bigint)
 returns numeric
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
    when exists (select 1 from public.sales_orders s2 join public.sales_reps rp on rp.id = s2.sales_rep_id
                 where s2.id = p_so and rp.komisi_flat_pct is not null)
      then coalesce((select r2.komisi from public.so_ringkas r2 where r2.so_id = p_so), 0)
    when s.telat and s.gm_pct is null then null
    when s.telat then coalesce(r.total_barang, 0) * s.gm_pct
    else coalesce(r.komisi, 0)
  end
  from public.sales_orders s left join public.so_ringkas r on r.so_id = s.id
  where s.id = p_so
$function$;

-- (10) Tambal definisi LIVE di tempat (fungsi panjang milik kelompok lain) — gagal keras bila
-- pola tak ketemu, supaya tidak ada yang diam-diam terlewat.
do $patch$
declare
  f regprocedure; d text; b text;
begin
  -- 10a. laporan margin: buang round() pada nilai uang; round(…, 1) persen margin DIBIARKAN
  foreach f in array array['public.laporan_margin_produk(date,date)'::regprocedure,
                           'public.laporan_margin_sp(date,date)'::regprocedure] loop
    d := pg_get_functiondef(f);
    b := replace(d, 'round((l.qty - l.qty_batal) * coalesce(l.harga_nett, 0))', '(l.qty - l.qty_batal) * coalesce(l.harga_nett, 0)');
    b := replace(b, 'round((l.qty - l.qty_batal) * coalesce(l.ehc_item, 0))',   '(l.qty - l.qty_batal) * coalesce(l.ehc_item, 0)');
    b := replace(b, 'round(b.qty * b.hpp_satuan)',                               '(b.qty * b.hpp_satuan)');
    if b = d or position('round((l.qty' in b) > 0 or position('round(b.qty' in b) > 0 then
      raise exception '#12 tambal %: pola round() tidak cocok dengan definisi live', f;
    end if;
    execute b;
  end loop;

  -- 10b. tautkan_po_sp: pembanding sampai sen + teks Rp bersen
  f := 'public.tautkan_po_sp(bigint,bigint)'::regprocedure;
  d := pg_get_functiondef(f);
  b := replace(d, 'if coalesce(v_sp,0) <> coalesce(v_nilai,0) then',
                  'if round(coalesce(v_sp,0), 2) <> round(coalesce(v_nilai,0), 2) then   -- #12: sama sampai sen');
  b := replace(b, 'to_char(abs(coalesce(v_sp,0) - coalesce(v_nilai,0)), ''FM999G999G999'')',
                  'public.rp_teks(abs(coalesce(v_sp,0) - coalesce(v_nilai,0)))');
  b := replace(b, 'to_char(v_sp, ''FM999G999G999'')',    'public.rp_teks(v_sp)');
  b := replace(b, 'to_char(v_nilai, ''FM999G999G999'')', 'public.rp_teks(v_nilai)');
  if position('FM999G999' in b) > 0 or position('round(coalesce(v_sp,0), 2)' in b) = 0 then
    raise exception '#12 tambal tautkan_po_sp: pola tidak cocok';
  end if;
  execute b;

  -- 10c. ajukan_klaim_ehc: batas nominal dibanding sampai sen + teks Rp
  -- (EHC 2,5 × 100,01 = 250,025 tampil "250,03" → nominal 250,03 harus diterima)
  f := 'public.ajukan_klaim_ehc(bigint,bigint,numeric,date,jsonb,text)'::regprocedure;
  d := pg_get_functiondef(f);
  b := replace(d, 'if p_nominal > v_ehc then raise exception ''Nominal % melebihi EHC di SP itu (%).'', p_nominal, v_ehc; end if;',
                  'if round(p_nominal, 2) > round(v_ehc, 2) then raise exception ''Nominal % melebihi EHC di SP itu (%).'', public.rp_teks(p_nominal), public.rp_teks(v_ehc); end if;   -- #12');
  if b = d then raise exception '#12 tambal ajukan_klaim_ehc: pola tidak cocok'; end if;
  execute b;

  -- 10d. pesan bernominal: to_char(x,'FM999G999G999[G999]') → rp_teks(x)
  foreach f in array array['public.putuskan_ubah(bigint,boolean,text)'::regprocedure,
                           'public.rekap_ehc_cepat()'::regprocedure] loop
    d := pg_get_functiondef(f);
    b := regexp_replace(d, 'to_char\(([^(),]+), ''FM999G999G999(G999)?''\)', 'public.rp_teks(\1)', 'g');
    if b = d or position('FM999G999' in b) > 0 then
      raise exception '#12 tambal %: pola to_char tidak cocok', f;
    end if;
    execute b;
  end loop;

  -- 10e. antrean_gm (view): teks keterangan bernominal
  d := pg_get_viewdef('public.antrean_gm'::regclass, true);
  b := regexp_replace(d, 'to_char\(([^()]*(\([^()]*\))?[^()]*), ''FM999G999G999''::text\)', 'rp_teks(\1)', 'g');
  if b = d or position('FM999G999' in b) > 0 then
    raise exception '#12 tambal antrean_gm: pola to_char tidak cocok';
  end if;
  execute 'create or replace view public.antrean_gm with (security_invoker = on) as ' || b;
end
$patch$;
