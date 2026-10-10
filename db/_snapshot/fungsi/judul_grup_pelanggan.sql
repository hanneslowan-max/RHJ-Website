CREATE OR REPLACE FUNCTION public.judul_grup_pelanggan(p_customer bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when g.id is null then null
    when public.kunci_nama_pelanggan(coalesce(nullif(btrim(g.nama_dokumen), ''), g.nama))
         = public.kunci_nama_pelanggan(c.nama) then null
    else coalesce(nullif(btrim(g.nama_dokumen), ''), btrim(g.nama)) || ' — Divisi '
         || btrim(regexp_replace(c.nama, '^(PT|CV|UD|PD|TB|Toko|Koperasi|Yayasan)\.?[[:space:]]+', '', 'i'))
  end
  from public.customers c
  left join public.customer_groups g on g.id = c.grup_id
  where c.id = p_customer
    and (auth.uid() is null or public.boleh_baca())
$function$;
