CREATE OR REPLACE FUNCTION public.kandidat_pelanggan_sp(p_so bigint)
 RETURNS TABLE(id bigint, nama text, sales text, cocok text, bisa boolean, alasan text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales_orders; v_k text; v_hp text; v_po_cust bigint;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner/GM yang menautkan SP ke pelanggan tertentu.' using errcode = '42501';
  end if;
  select * into s from public.sales_orders x where x.id = p_so;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002'; end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));
  if char_length(coalesce(v_k, '')) < 2 then v_k := null; end if;
  v_hp := public.hp_baku(s.telp);
  if s.po_id is not null then
    select p.customer_id into v_po_cust from public.purchase_orders p where p.id = s.po_id;
  end if;
  return query
    with c as (
      select x.id, x.nama, sr.nama as sales,
             case when v_k is not null and (public.kunci_nama_pelanggan(x.nama) = v_k
                       or (x.nama_lama is not null and public.kunci_nama_pelanggan(x.nama_lama) = v_k))
                  then 'nama' else 'hp' end as cocok,
             case when x.blacklist then 'pelanggan daftar hitam'
                  when public.sp_pelanggan_hitam(x.id, null, null, null) is not null
                    then 'cocok nama/No. HP dengan pelanggan daftar hitam'   -- 139s
                  when x.sales_rep_id is not null and s.sales_rep_id is not null and x.sales_rep_id <> s.sales_rep_id
                    then 'dipegang sales ' || coalesce(sr.nama, 'lain') || ', bukan sales SP ini'
                  when v_po_cust is not null and v_po_cust <> x.id then 'PO SP ini atas nama pelanggan lain'
             end as alasan
        from public.customers x left join public.sales_reps sr on sr.id = x.sales_rep_id
       where (v_k is not null and (public.kunci_nama_pelanggan(x.nama) = v_k
                                   or (x.nama_lama is not null and public.kunci_nama_pelanggan(x.nama_lama) = v_k)))
          or (v_hp is not null and x.hp = v_hp))
    select c.id, c.nama, c.sales, c.cocok, c.alasan is null, c.alasan
      from c
     order by (c.alasan is null) desc, (c.cocok = 'nama') desc, c.id
     limit 10;
end $function$;
