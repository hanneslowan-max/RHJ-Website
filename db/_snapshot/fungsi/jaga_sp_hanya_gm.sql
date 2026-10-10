CREATE OR REPLACE FUNCTION public.jaga_sp_hanya_gm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nama text;
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;
  if not public.sp_khusus_gm(new.sales_rep_id, new.customer_id) then return new; end if;
  -- SP yang memang sudah milik Office boleh dikerjakan peran lain (cek Vonny, tautkan
  -- pelanggan, dst.) — yang ditolak hanya membuat atau MENGALIHKAN SP ke Office.
  if tg_op = 'UPDATE' and public.sp_khusus_gm(old.sales_rep_id, old.customer_id) then
    return new;
  end if;
  select r.nama into v_nama
    from public.sales_reps r
   where r.sp_hanya_gm
     and (r.id = new.sales_rep_id
          or r.id = (select c.sales_rep_id from public.customers c where c.id = new.customer_id))
   limit 1;
  raise exception 'SP untuk pelanggan % hanya dibuat GM atau owner (pelanggan kantor, tanpa komisi). '
                  'Minta GM yang membuatkan SP-nya.', coalesce(v_nama, 'Office')
    using errcode = '42501';
end $function$;
