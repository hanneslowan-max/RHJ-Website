CREATE OR REPLACE FUNCTION public.pindah_semua_pelanggan(p_dari bigint, p_ke bigint, p_alasan text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int; v_dari text; v_ke text;
begin
  if public.peran_saya() not in ('owner','gm') then
    raise exception 'Hanya owner atau GM yang boleh memindahkan seluruh pelanggan seorang sales.'
      using errcode = '42501';
  end if;
  if p_dari is null then
    raise exception 'Sales asal wajib disebut.' using errcode = '22023';
  end if;
  if p_dari = p_ke then
    raise exception 'Sales asal dan tujuan sama.' using errcode = '22023';
  end if;
  select nama into v_dari from public.sales_reps where id = p_dari;
  if v_dari is null then
    raise exception 'Sales asal #% tidak ada.', p_dari using errcode = 'P0002';
  end if;
  if p_ke is not null then
    select nama into v_ke from public.sales_reps where id = p_ke;
    if v_ke is null then
      raise exception 'Sales tujuan #% tidak ada.', p_ke using errcode = 'P0002';
    end if;
  end if;

  update public.customers
     set sales_rep_id = p_ke, diubah_pada = now(), diubah_oleh = auth.uid()
   where sales_rep_id = p_dari;
  get diagnostics n = row_count;

  return n || ' pelanggan dipindahkan dari ' || v_dari || ' ke '
         || coalesce(v_ke, 'tanpa sales')
         || case when coalesce(btrim(p_alasan),'') <> '' then ' (' || btrim(p_alasan) || ')' else '' end
         || '. Lead dan Surat Pesanan yang sudah ada TIDAK ikut berpindah — komisinya '
         || 'tetap milik yang mengerjakannya.';
end $function$;
