-- Berkas 91 (#26): laporan penjualan per kategori produk.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026. Belum ke produksi.
--
-- laporan_penjualan(p_dari, p_sampai, p_dimensi) — CREATE OR REPLACE dengan tanda tangan dan
-- RETURNS TABLE yang SAMA PERSIS, jadi grant tetap berlaku dan index.html lama tidak terganggu.
-- Disalin dari versi live di DEV (pg_get_functiondef, 28 Sep 2026); cabang "sales"/"pelanggan"
-- tidak berubah sama sekali.
--
-- Perubahan:
--   (1) potongan baru "kategori": satu baris per kategori produk (products.kategori, berkas 90).
--       Seperti potongan "produk", Grand Total & Komisi sengaja null (SP lintas kategori akan
--       terhitung berkali-kali), dan SP yang memuat dua kategori terhitung di keduanya pada
--       kolom jumlah_sp. Kolom rinci = jumlah produk berbeda yang terjual di kategori itu.
--   (2) potongan "produk": rinci kini "brand · kategori" (dulu brand saja).
--   (3) potongan "produk" & "kategori" membaca baris dari view so_baris_hitung — sumber yang sama
--       dengan so_ringkas (yang dipakai potongan sales/pelanggan). Akibatnya baris SP yang DIBATALKAN
--       (#73, sales_order_lines.batal) tidak lagi ikut terhitung di potongan produk; sebelumnya
--       ikut (DEV saat ini: 0 baris batal, jadi angka tidak berubah). Aturan pembulatan nilai baris
--       (#12) cukup diatur di satu tempat: so_baris_hitung.
--
-- Invarian (diuji): jumlah nilai_barang potongan kategori = potongan produk = potongan sales
-- untuk periode yang sama.

create or replace function public.laporan_penjualan(
  p_dari date default null::date,
  p_sampai date default null::date,
  p_dimensi text default 'sales'::text)
returns table(kunci text, rinci text, jumlah_sp bigint, qty numeric, nilai_barang numeric,
              nilai_ehc numeric, nilai_biaya numeric, grand_total numeric, komisi numeric)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_dim text; v_rep bigint; v_komisi boolean;
begin
  if not public.boleh_laporan() then
    raise exception 'Anda tidak berwenang membuka laporan penjualan.' using errcode = '42501';
  end if;
  v_dim := lower(coalesce(nullif(btrim(p_dimensi), ''), 'sales'));
  if v_dim not in ('sales','pelanggan','produk','kategori') then   -- #26: + kategori
    raise exception 'Potongan laporan hanya boleh "sales", "pelanggan", "produk", atau "kategori" — bukan "%".',
      p_dimensi using errcode = '22023';
  end if;
  v_rep := public.laporan_rep_saring();
  -- Komisi hanya ditampilkan kepada yang memang boleh melihat nominal
  -- klaim, atau kepada sales untuk barisnya sendiri. Untuk yang lain
  -- kolomnya null — bukan nol, karena nol terbaca sebagai "tidak ada
  -- komisi" dan itu keterangan yang salah.
  v_komisi := public.boleh_lihat_nilai_klaim() or public.peran_saya() = 'sales';

  -- Dua jalan, bukan satu query pintar. Potongan "produk" (dan "kategori")
  -- memecah SP jadi beberapa baris, jadi grand total dan komisi TIDAK boleh
  -- dijumlahkan di sana — SP dengan lima baris akan terhitung lima kali.
  -- Menuliskannya sebagai cabang terpisah membuat perbedaan itu terbaca,
  -- bukan tersembunyi di dalam satu `case` yang harus dipercaya.
  --
  -- #26: baris dibaca dari so_baris_hitung (sumber yang sama dengan
  -- so_ringkas): baris batal (#73) tidak ikut, dan nilai baris dihitung di
  -- satu tempat saja.
  if v_dim = 'produk' then
    return query
      select coalesce(p.kode, '(tanpa kode)')::text                    as kunci,
             concat_ws(' · ', nullif(p.brand, ''), p.kategori)::text   as rinci,   -- #26: kategori ikut
             count(distinct s.id)                                      as jumlah_sp,
             sum(b.qty)                                                as qty,
             coalesce(sum(b.nilai_barang), 0)                          as nilai_barang,
             coalesce(sum(b.nilai_ehc), 0)                             as nilai_ehc,
             0::numeric                                                as nilai_biaya,
             null::numeric                                             as grand_total,
             null::numeric                                             as komisi
        from public.sales_orders s
        join public.so_baris_hitung b on b.so_id = s.id
        left join public.products p on p.id = b.product_id
       where not s.batal
         and b.jenis <> 'biaya'
         and (p_dari   is null or s.tanggal >= p_dari)
         and (p_sampai is null or s.tanggal <= p_sampai)
         and (v_rep is null or s.sales_rep_id = v_rep)
       group by 1, 2
       order by 5 desc;
    return;
  end if;

  if v_dim = 'kategori' then   -- #26: ringkasan per kategori produk
    return query
      select coalesce(p.kategori, '(tanpa kategori)')::text            as kunci,
             (count(distinct b.product_id)::text || ' produk')::text   as rinci,
             count(distinct s.id)                                      as jumlah_sp,
             sum(b.qty)                                                as qty,
             coalesce(sum(b.nilai_barang), 0)                          as nilai_barang,
             coalesce(sum(b.nilai_ehc), 0)                             as nilai_ehc,
             0::numeric                                                as nilai_biaya,
             -- null, bukan nol: SP lintas kategori akan terhitung berkali-kali
             null::numeric                                             as grand_total,
             null::numeric                                             as komisi
        from public.sales_orders s
        join public.so_baris_hitung b on b.so_id = s.id
        left join public.products p on p.id = b.product_id
       where not s.batal
         and b.jenis <> 'biaya'
         and (p_dari   is null or s.tanggal >= p_dari)
         and (p_sampai is null or s.tanggal <= p_sampai)
         and (v_rep is null or s.sales_rep_id = v_rep)
       group by 1
       order by 5 desc;
    return;
  end if;

  -- Potongan "sales" dan "pelanggan": satu SP milik satu sales dan satu
  -- pelanggan, jadi dijumlahkan PER SP lebih dulu — baru dikelompokkan.
  return query
  with sp as (
    select s.id, s.sales_rep_id, s.customer_id, s.kepada,
           coalesce(r.total_barang, 0) as nilai_barang,
           coalesce(r.total_ehc, 0)    as nilai_ehc,
           coalesce(r.total_biaya, 0)  as nilai_biaya,
           coalesce(r.grand_total, 0)  as grand_total,
           coalesce(r.komisi, 0)       as komisi
      from public.sales_orders s
      left join public.so_ringkas r on r.so_id = s.id
     where not s.batal
       and (p_dari   is null or s.tanggal >= p_dari)
       and (p_sampai is null or s.tanggal <= p_sampai)
       and (v_rep is null or s.sales_rep_id = v_rep)
  )
  select case when v_dim = 'sales' then coalesce(sr.nama, '(tanpa sales)')
              else coalesce(c.nama, sp.kepada, '(tanpa pelanggan)') end::text as kunci,
         case when v_dim = 'sales' then coalesce(sr.jenis, '')
              else coalesce(c.cabang, '') end::text                           as rinci,
         count(*)                                                             as jumlah_sp,
         null::numeric                                                        as qty,
         sum(sp.nilai_barang)                                                 as nilai_barang,
         sum(sp.nilai_ehc)                                                    as nilai_ehc,
         sum(sp.nilai_biaya)                                                  as nilai_biaya,
         sum(sp.grand_total)                                                  as grand_total,
         -- null, bukan nol: nol terbaca sebagai "tidak ada komisi", dan itu
         -- keterangan yang salah untuk orang yang memang tidak boleh
         -- melihat angkanya.
         case when v_komisi then sum(sp.komisi) else null end                 as komisi
    from sp
    left join public.sales_reps sr on sr.id = sp.sales_rep_id
    left join public.customers  c  on c.id  = sp.customer_id
   group by 1, 2
   order by 5 desc;
end $function$;

revoke execute on function public.laporan_penjualan(date, date, text) from public, anon;
grant  execute on function public.laporan_penjualan(date, date, text) to authenticated;
