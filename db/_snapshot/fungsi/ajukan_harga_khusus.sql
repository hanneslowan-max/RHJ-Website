CREATE OR REPLACE FUNCTION public.ajukan_harga_khusus(p_customer bigint, p_items jsonb, p_alasan text, p_so bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x jsonb; v_n int := 0; v_nett numeric; v_prod bigint; v_ada public.harga_khusus;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengajukan harga khusus.';
  end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Alasan permintaan harga khusus wajib diisi.';
  end if;
  if p_customer is null then
    raise exception 'Harga khusus menempel pada satu perusahaan — pilih customernya dulu.';
  end if;
  if not public.pic_pelanggan_saya(p_customer) then
    raise exception 'Pelanggan ini bukan pelanggan Anda. Harga khusus menempel pada '
                    'perusahaannya, jadi hanya sales yang memegangnya yang boleh '
                    'mengajukan.' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Tidak ada item yang diajukan.';
  end if;

  for x in select * from jsonb_array_elements(p_items) loop
    v_prod := nullif(x->>'product_id', '')::bigint;
    v_nett := nullif(x->>'harga_nett', '')::numeric;
    if v_prod is null then raise exception 'Ada item tanpa product_id.'; end if;
    if v_nett is null or v_nett <= 0 then
      raise exception 'Harga nett untuk item % belum diisi.', v_prod;
    end if;

    select * into v_ada from public.harga_khusus
     where customer_id = p_customer and product_id = v_prod
       and status in ('menunggu','aktif');

    if found and v_ada.status = 'aktif' and v_nett >= v_ada.harga_nett then
      continue;
    end if;
    if found and v_ada.status = 'menunggu' then
      update public.harga_khusus
         set harga_nett = least(harga_nett, v_nett),
             ehc_item   = coalesce(nullif(x->>'ehc_item','')::numeric, ehc_item),
             alasan     = btrim(p_alasan),
             so_id      = coalesce(so_id, p_so),
             diajukan_pada = now(), diajukan_oleh = auth.uid()
       where id = v_ada.id;
      v_n := v_n + 1;
      continue;
    end if;
    if found and v_ada.status = 'aktif' then
      update public.harga_khusus set status = 'nonaktif',
             diputus_oleh = auth.uid(), diputus_pada = now()
       where id = v_ada.id;
      insert into public.harga_khusus_log
        (harga_khusus_id, lama_harga, lama_ehc, lama_pct, lama_status,
         harga_nett, ehc_item, komisi_pct, status, catatan, diubah_oleh)
      values (v_ada.id, v_ada.harga_nett, v_ada.ehc_item, v_ada.komisi_pct, 'aktif',
              v_ada.harga_nett, v_ada.ehc_item, v_ada.komisi_pct, 'nonaktif',
              'Diganti permintaan harga yang lebih rendah', auth.uid());
    end if;

    insert into public.harga_khusus
      (customer_id, product_id, harga_nett, ehc_item, alasan, so_id, diajukan_oleh)
    values (p_customer, v_prod, v_nett,
            coalesce(nullif(x->>'ehc_item','')::numeric, 0),
            btrim(p_alasan), p_so, auth.uid());
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
