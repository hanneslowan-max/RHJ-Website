CREATE OR REPLACE FUNCTION public.nama_pelanggan_kembar(p_nama text, p_kecuali bigint DEFAULT NULL::bigint)
 RETURNS TABLE(id bigint, nama text, sales text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_k text := public.kunci_nama_pelanggan(public.rhj_nama_rapi(p_nama));   -- 139r
begin
  if auth.uid() is null or not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Pemeriksaan nama pelanggan hanya untuk peran yang mengelola pelanggan.' using errcode = '42501';
  end if;
  if coalesce(v_k, '') = '' then return; end if;
  return query
    select c.id, c.nama, sr.nama
      from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
     where c.id is distinct from p_kecuali
       and (public.kunci_nama_pelanggan(c.nama) = v_k
            or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k))
     order by c.id limit 5;
end $function$;
