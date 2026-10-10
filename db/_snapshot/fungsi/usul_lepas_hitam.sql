CREATE OR REPLACE FUNCTION public.usul_lepas_hitam(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u public.usul_ubah; s public.sales_orders; k jsonb; v_lama bigint; v_c public.customers;
begin
  if auth.uid() is null or not public.boleh_approve() then return null; end if;
  select * into u from public.usul_ubah where id = p_id;
  if u.id is null or u.jenis <> 'sp' or u.status <> 'menunggu' then return null; end if;
  select * into s from public.sales_orders where id = u.ref_id;
  if s.id is null then return null; end if;
  k := u.nilai_baru -> 'kepala';
  v_lama := public.sp_pelanggan_hitam(s.customer_id, s.po_id, s.kepada, s.telp);
  if v_lama is null
     or public.sp_pelanggan_hitam(s.customer_id, s.po_id, coalesce(k->>'kepada', s.kepada), coalesce(k->>'telp', s.telp))
        is not null then
    return null;                                   -- tidak tertahan, atau tetap tertahan sesudahnya
  end if;
  select * into v_c from public.customers where id = v_lama;
  return 'SP ' || s.no_sp || ' tertahan karena cocok dengan pelanggan daftar hitam "' || v_c.nama || '" ('
      || coalesce(v_c.alasan_blacklist, 'tanpa keterangan') || ') — menyetujui perubahan Kepada/No. HP ini MELEPAS '
      || 'penahanannya';
end $function$;
