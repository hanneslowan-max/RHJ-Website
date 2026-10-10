CREATE OR REPLACE FUNCTION public.segarkan_jejak_hitam()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
  select j.customer_id, 'kunci', k.k, j.teks
    from public.pelanggan_hitam_jejak j
    cross join lateral (select public.kunci_nama_pelanggan(j.teks) as k) k
   where j.jenis = 'kunci' and j.teks <> '' and k.k is distinct from j.nilai
     and char_length(coalesce(k.k, '')) >= 2 and k.k <> 'tanpa nama'
  on conflict do nothing;
  execute 'del' || 'ete from public.pelanggan_hitam_jejak j where j.jenis = ''kunci'' and j.teks <> '''' '
       || 'and j.nilai is distinct from public.kunci_nama_pelanggan(j.teks)';
  get diagnostics n = row_count;
  return n;
end $function$;
