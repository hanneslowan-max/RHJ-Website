CREATE OR REPLACE FUNCTION public.laporan_piutang(p_per date DEFAULT NULL::date)
 RETURNS TABLE(no_sp text, no_invoice text, tgl_invoice date, kepada text, sales text, umur_hari integer, kelompok text, no_faktur text, tgl_surat_jalan date, grand_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Ditolak dengan BERBUNYI, bukan dengan mengembalikan nol baris. Laporan
  -- kosong dan laporan terlarang terlihat sama persis di layar, dan orang
  -- yang salah membacanya akan menyimpulkan "bulan ini tidak ada piutang".
  if not public.boleh_laporan() then
    raise exception 'Anda tidak berwenang membuka laporan piutang.' using errcode = '42501';
  end if;
  return query
  with per as (select coalesce(p_per, current_date) as d),
       saring as (select public.laporan_rep_saring() as rep)
  select s.no_sp,
         s.no_invoice,
         s.tgl_invoice,
         s.kepada,
         coalesce(r.nama, '—')                        as sales,
         (per.d - s.tgl_invoice)::integer             as umur_hari,
         case
           when (per.d - s.tgl_invoice) <=  30 then '1 · 0-30 hari'
           when (per.d - s.tgl_invoice) <=  60 then '2 · 31-60 hari'
           when (per.d - s.tgl_invoice) <=  90 then '3 · 61-90 hari'
           when (per.d - s.tgl_invoice) <= 120 then '4 · 91-120 hari — hampir batas'
           else                                     '5 · LEWAT 120 hari'
         end                                          as kelompok,
         s.no_faktur,
         s.tgl_surat_jalan,
         coalesce(ring.grand_total, 0)                as grand_total
    from public.sales_orders s
    cross join per
    cross join saring
    left join public.sales_reps r  on r.id = s.sales_rep_id
    left join public.so_ringkas ring on ring.so_id = s.id
   where not s.batal
     and s.no_invoice is not null
     and s.tgl_invoice is not null
     and not s.lunas
     and (saring.rep is null or s.sales_rep_id = saring.rep)
   order by (per.d - s.tgl_invoice) desc, s.no_invoice;
end $function$;
