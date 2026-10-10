CREATE OR REPLACE FUNCTION public.laporan_hpp_kosong()
 RETURNS TABLE(kode text, brand text, kelompok text, harga_list numeric, pernah_dijual boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.boleh_laporan_margin() then
    raise exception 'Daftar HPP kosong hanya untuk owner, GM, dan finance.'
      using errcode = '42501';
  end if;

  return query
  select p.kode,
         coalesce(p.brand, '')::text,
         coalesce(p.kelompok, '')::text,
         public.harga_berlaku_hitung(p.id, current_date),
         exists (select 1 from public.sales_order_lines l
                  join public.sales_orders s on s.id = l.so_id
                 where l.product_id = p.id and not s.batal)
    from public.products p
   where not coalesce(p.usulan, false)
     and coalesce(p.aktif, true)
     and public.hpp_berlaku(p.id, current_date) is null
   order by 5 desc, p.kode;
end $function$;
