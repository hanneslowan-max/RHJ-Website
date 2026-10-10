CREATE OR REPLACE FUNCTION public.sp_pelanggan_hitam_rinci(p_customer bigint, p_po bigint, p_kepada text, p_telp text)
 RETURNS TABLE(id bigint, cara text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_c bigint := p_customer; c public.customers; v_k text; v_hp text; v_id bigint; v_dari_po boolean := false;
begin
  if v_c is null and p_po is not null then
    select p.customer_id into v_c from public.purchase_orders p where p.id = p_po;
    v_dari_po := v_c is not null;
  end if;
  if v_c is not null then
    select * into c from public.customers x where x.id = v_c;
    if c.id is not null then
      if c.blacklist then id := c.id; cara := 'pelanggan'; return next; return; end if;
      -- 139x: nama asli kembaran dihitung hanya selama masih nama asli dari nama sekarang
      v_id := public.pelanggan_hitam_cocok(
                array_remove(array[nullif(public.kunci_nama_pelanggan(c.nama), ''),
                                   case when c.nama_lama is not null
                                             and public.rhj_nama_sidik(c.nama) = public.rhj_nama_sidik(c.nama_lama)
                                        then nullif(public.kunci_nama_pelanggan(c.nama_lama), '') end], null),
                c.hp, c.id);
      if v_id is not null then id := v_id; cara := 'kembar'; return next; return; end if;
    end if;
    -- SP tertaut: hanya pelanggan itu (dan kembarannya) yang menentukan. 139y (review 139x no. 7): SP yang BELUM tertaut
    -- tetap diperiksa nama/No. HP-nya sendiri walau PO-nya sudah tertaut (PO bisa tertaut lewat SP lain)
    if not v_dari_po then return; end if;
  end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(p_kepada));
  if char_length(coalesce(v_k, '')) >= 2 then
    v_id := public.pelanggan_hitam_cocok(array[v_k], null, null);
    if v_id is not null then id := v_id; cara := 'nama'; return next; return; end if;
  end if;
  v_hp := public.hp_baku(p_telp);
  if v_hp is not null then
    v_id := public.pelanggan_hitam_cocok('{}'::text[], v_hp, null);
    if v_id is not null then id := v_id; cara := 'hp'; return next; end if;
  end if;
end $function$;
