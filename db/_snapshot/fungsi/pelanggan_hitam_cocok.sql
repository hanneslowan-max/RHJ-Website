CREATE OR REPLACE FUNCTION public.pelanggan_hitam_cocok(p_kunci text[], p_hp text, p_kecuali bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id
    from public.customers c,
         (select array_remove(coalesce(p_kunci, '{}'::text[]), 'tanpa nama') as k) a   -- 139x: nama pengganti
   where c.blacklist and c.id is distinct from p_kecuali
     and (public.kunci_nama_pelanggan(c.nama) = any (a.k)
          or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = any (a.k))
          or (p_hp is not null and c.hp = p_hp)
          or exists (select 1 from public.pelanggan_hitam_jejak j
                      where j.customer_id = c.id
                        and ((j.jenis = 'kunci' and j.nilai = any (a.k)) or (j.jenis = 'hp' and j.nilai = p_hp))))
   order by c.id
   limit 1
$function$;
