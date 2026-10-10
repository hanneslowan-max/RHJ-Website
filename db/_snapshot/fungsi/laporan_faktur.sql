CREATE OR REPLACE FUNCTION public.laporan_faktur(p_dari date DEFAULT NULL::date, p_sampai date DEFAULT NULL::date)
 RETURNS TABLE(no_faktur text, tgl_faktur date, no_invoice text, tgl_invoice date, no_sp text, kepada text, dasar_ppn numeric, ppn numeric, grand_total numeric, lunas boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.boleh_lihat_semua_jual() then
    raise exception 'Rekap faktur pajak hanya untuk staf kantor dan finance — '
                    'bukan untuk peran sales.' using errcode = '42501';
  end if;
  return query
  select s.no_faktur,
         s.tgl_faktur,
         s.no_invoice,
         s.tgl_invoice,
         s.no_sp,
         s.kepada,
         coalesce(r.dasar_ppn, 0)   as dasar_ppn,
         coalesce(r.ppn, 0)         as ppn,
         coalesce(r.grand_total, 0) as grand_total,
         s.lunas
    from public.sales_orders s
    left join public.so_ringkas r on r.so_id = s.id
   where not s.batal
     and s.no_faktur is not null
     and s.tgl_faktur is not null
     and (p_dari   is null or s.tgl_faktur >= p_dari)
     and (p_sampai is null or s.tgl_faktur <= p_sampai)
   order by s.tgl_faktur, s.no_faktur;
end $function$;
