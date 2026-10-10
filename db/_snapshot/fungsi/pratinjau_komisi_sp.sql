CREATE OR REPLACE FUNCTION public.pratinjau_komisi_sp(p_sales_rep bigint, p_customer bigint, p_mode_ppn text, p_cash_minta boolean, p_baris jsonb, p_po bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_peran   text := public.peran_saya();
  v_rep     bigint := p_sales_rep;
  v_cust    bigint := p_customer;
  v_mode    text := coalesce(nullif(btrim(coalesce(p_mode_ppn, '')), ''), 'exclude');
  v_cash    boolean := coalesce(p_cash_minta, false);
  v_flat    numeric;
  v_cash_only boolean;
  v_hanya_gm boolean;
  v_po      record;
  e         jsonb;
  v_n       int := 0;
  v_i       int;
  v_jenis   text;
  v_prod    bigint;
  v_qty     numeric;
  v_nett    numeric;
  v_dpp     numeric;
  v_list    numeric;
  v_hammer  boolean;
  v_hk_id   bigint;
  v_hk_pct  numeric;
  v_pct     numeric;
  v_pct_c   numeric;
  v_status  text;
  v_nilai   numeric;
  v_tunggu  boolean;
  v_perlu   boolean;
  v_baris   jsonb := '[]'::jsonb;
  v_total   numeric := 0;
  v_total_c numeric := 0;
  v_ada_c   boolean := false;
  v_n_bawah int := 0;
  v_n_tanpa int := 0;
  v_n_flat  int := 0;
  v_dasar   numeric := 0;
begin
  if auth.uid() is null or not public.boleh_alur_jual() then
    raise exception 'Perkiraan komisi hanya untuk pembuat Surat Pesanan (sales, staff, GM, owner).' using errcode = '42501';
  end if;
  if p_baris is null or jsonb_typeof(p_baris) <> 'array' then
    raise exception 'Baris pratinjau harus berupa daftar.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_baris) > 300 then
    raise exception 'Terlalu banyak baris untuk dipratinjau (maks 300).' using errcode = '22023';
  end if;

  if p_po is not null then
    select p.id, p.mode_ppn, p.customer_id, p.sales_rep_id into v_po from public.purchase_orders p where p.id = p_po;
    if v_po.id is null then raise exception 'PO #% tidak ditemukan.', p_po using errcode = 'P0002'; end if;
    if v_peran = 'sales' and v_po.sales_rep_id is distinct from public.sales_rep_saya() then
      raise exception 'PO ini bukan milik Anda.' using errcode = '42501';
    end if;
    v_mode := coalesce(v_po.mode_ppn, v_mode);
    v_cust := v_po.customer_id;
    v_rep  := coalesce(v_rep, v_po.sales_rep_id);
  end if;
  if v_mode not in ('exclude', 'include', 'non') then
    raise exception 'Mode PPN hanya exclude, include, atau non.' using errcode = '22023';
  end if;

  if v_peran = 'sales' then
    if public.sales_rep_saya() is null then
      raise exception 'Akun sales Anda belum ditautkan ke data sales.' using errcode = '42501';
    end if;
    if v_rep is not null and v_rep <> public.sales_rep_saya() then
      raise exception 'Sales SP harus diri Anda sendiri.' using errcode = '42501';
    end if;
    v_rep := public.sales_rep_saya();
  end if;
  if not public.pelanggan_saya(v_cust) then
    raise exception 'Pelanggan ini dipegang sales lain.' using errcode = '42501';
  end if;
  if not public.setara_owner() and public.sp_khusus_gm(v_rep, v_cust) then
    raise exception 'SP untuk pelanggan Office hanya dibuat GM atau owner (pelanggan kantor, tanpa komisi). Minta GM yang membuatkan SP-nya.'
      using errcode = '42501';
  end if;
  select r.komisi_flat_pct, coalesce(r.cash_only, false), coalesce(r.sp_hanya_gm, false)
    into v_flat, v_cash_only, v_hanya_gm from public.sales_reps r where r.id = v_rep;
  if v_cash_only then v_cash := true; end if;

  for e in select x from jsonb_array_elements(p_baris) as t(x) loop
    v_n := v_n + 1;
    v_i := coalesce(nullif(e->>'i', '')::int, v_n - 1);
    v_jenis := coalesce(nullif(e->>'jenis', ''), 'barang');
    v_prod := case when v_jenis = 'biaya' then null else nullif(e->>'product_id', '')::bigint end;
    v_qty := coalesce(nullif(e->>'qty', '')::numeric, 0);
    v_nett := coalesce(nullif(e->>'harga_nett', '')::numeric, 0);
    v_dpp := public.dpp_ppn(v_nett, v_mode, v_jenis);
    v_list := case when v_prod is null then null else public.harga_berlaku_hitung(v_prod, current_date) end;
    v_hammer := coalesce((select upper(coalesce(pr.brand, '')) = 'HAMMER' from public.products pr where pr.id = v_prod), false);
    v_hk_id := null; v_hk_pct := null;
    if v_jenis <> 'biaya' and v_cust is not null and v_prod is not null
       and (coalesce(v_list, 0) <= 0 or v_dpp < v_list) then
      select h.id, h.komisi_pct into v_hk_id, v_hk_pct from public.harga_khusus h
       where h.status = 'aktif' and h.customer_id = v_cust and h.product_id = v_prod and v_dpp >= h.harga_nett
       order by h.id desc limit 1;
    end if;
    v_pct := public.komisi_pct_baris(v_jenis, v_flat, v_hk_id is not null, v_hk_pct, null, v_dpp, v_list, v_hammer);
    v_pct_c := case when v_cash and v_flat is null and v_hk_id is null and v_jenis <> 'biaya'
                    then public.komisi_tier_cash(v_dpp, v_list) end;
    v_nilai := v_qty * v_dpp;
    v_tunggu := false;
    v_perlu := v_qty > 0 and v_jenis = 'barang'
               and (v_pct is null
                    or (v_flat is not null and not v_hanya_gm and v_hk_id is null
                        and coalesce(v_list, 0) > 0 and v_dpp < v_list));
    v_status := case
      when v_qty <= 0              then 'kosong'
      when v_jenis = 'biaya'       then 'biaya'
      when v_flat is not null      then 'flat'
      when v_hk_id is not null     then 'khusus'
      when v_pct is not null       then 'tier'
      when coalesce(v_list, 0) > 0 then 'bawah_list'
      else 'tanpa_list' end;
    if v_status in ('bawah_list', 'tanpa_list') then
      if v_status = 'bawah_list' then v_n_bawah := v_n_bawah + 1; else v_n_tanpa := v_n_tanpa + 1; end if;
      v_dasar := v_dasar + v_nilai;
    end if;
    if v_status = 'flat' and v_perlu then v_n_flat := v_n_flat + 1; end if;
    if v_perlu and v_cust is not null and v_prod is not null then
      v_tunggu := exists (select 1 from public.harga_khusus h
                           where h.status = 'menunggu' and h.customer_id = v_cust and h.product_id = v_prod);
    end if;
    if v_qty > 0 then
      v_total := v_total + coalesce(v_nilai * v_pct, 0);
      if v_pct_c is not null then v_ada_c := true; end if;
      v_total_c := v_total_c + coalesce(v_nilai * coalesce(v_pct_c, v_pct), 0);
    end if;
    v_baris := v_baris || jsonb_build_object(
      'i', v_i, 'product_id', v_prod, 'jenis', v_jenis, 'nett_dpp', v_dpp, 'harga_list', v_list,
      'nilai_dpp', v_nilai, 'pct', v_pct, 'komisi', case when v_qty > 0 then v_nilai * v_pct end,
      'status', v_status, 'pct_bila_cash', v_pct_c,
      'komisi_bila_cash', case when v_qty > 0 and v_pct_c is not null then v_nilai * v_pct_c end,
      'harga_khusus_id', v_hk_id, 'harga_khusus_menunggu', v_tunggu, 'perlu_gm', v_perlu);
  end loop;

  return jsonb_build_object(
    'baris', v_baris, 'komisi', v_total,
    'komisi_bila_cash', case when v_ada_c then v_total_c end,
    'n_bawah_list', v_n_bawah, 'n_tanpa_list', v_n_tanpa, 'n_flat_gm', v_n_flat, 'dasar_menunggu', v_dasar,
    'flat_pct', v_flat, 'sales_rep_id', v_rep, 'customer_id', v_cust, 'mode_ppn', v_mode,
    'cash_minta', v_cash, 'tanggal', current_date);
end $function$;
