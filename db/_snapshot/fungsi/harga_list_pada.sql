CREATE OR REPLACE FUNCTION public.harga_list_pada(p_product bigint, p_tgl date, p_waktu timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with calon as (
    select pl.id from public.price_list pl where pl.product_id = p_product
    union
    select a.baris_id from public.audit_log a
     where a.tabel = 'price_list' and a.aksi not in ('INSERT', 'UPDATE') and a.pada > p_waktu
       and a.sebelum ->> 'product_id' = p_product::text
  ), keadaan as (
    select coalesce(
             (select a.sebelum from public.audit_log a
               where a.tabel = 'price_list' and a.baris_id = c.id and a.aksi <> 'INSERT' and a.pada > p_waktu
               order by a.pada, a.id limit 1),
             (select to_jsonb(pl) from public.price_list pl where pl.id = c.id)) as r
      from calon c
  )
  select (k.r ->> 'harga')::numeric
    from keadaan k
   where k.r is not null and k.r ->> 'product_id' = p_product::text
     and (k.r ->> 'berlaku_dari')::date <= p_tgl
     and (k.r ->> 'dibuat_pada')::timestamptz <= p_waktu
   order by (k.r ->> 'berlaku_dari')::date desc, (k.r ->> 'id')::bigint desc
   limit 1
$function$;
