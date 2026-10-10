CREATE OR REPLACE FUNCTION public.pindah_sales_pelanggan(p_customer bigint, p_rep bigint, p_alasan text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; v_lama text; v_baru text;
begin
  if public.peran_saya() not in ('owner','gm','staff') then
    raise exception 'Hanya owner, GM, atau staff yang boleh memindahkan pelanggan.'
      using errcode = '42501';
  end if;
  select * into v from public.customers where id = p_customer;
  if v.id is null then
    raise exception 'Pelanggan #% tidak ditemukan.', p_customer using errcode = 'P0002';
  end if;
  if p_rep is not null and not exists (select 1 from public.sales_reps where id = p_rep) then
    raise exception 'Sales #% tidak ada.', p_rep using errcode = 'P0002';
  end if;
  if v.sales_rep_id is not distinct from p_rep then
    raise exception 'Pelanggan % memang sudah dipegang sales itu.', v.nama using errcode = '22023';
  end if;

  select nama into v_lama from public.sales_reps where id = v.sales_rep_id;
  select nama into v_baru from public.sales_reps where id = p_rep;

  update public.customers
     set sales_rep_id = p_rep, diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_customer;

  return v.nama || ': ' || coalesce(v_lama, 'belum bertuan') || ' → '
         || coalesce(v_baru, 'dikosongkan')
         || case when coalesce(btrim(p_alasan),'') <> '' then ' (' || btrim(p_alasan) || ')' else '' end;
end $function$;
