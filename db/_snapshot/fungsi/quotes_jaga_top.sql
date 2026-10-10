CREATE OR REPLACE FUNCTION public.quotes_jaga_top()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cash boolean; v_nama text;
begin
  select r.cash_only, r.nama into v_cash, v_nama from public.sales_reps r where r.id = new.sales_rep_id;
  if coalesce(v_cash, false) then
    if new.top is null or btrim(new.top) = '' then
      new.top := 'Cash';
    elsif lower(btrim(new.top)) <> 'cash' then
      raise exception 'Penawaran atas nama % hanya boleh TOP Cash — sales ini wajib cash.', coalesce(v_nama, 'sales ini')
        using errcode = '23514';
    else
      new.top := 'Cash';
    end if;
  end if;
  return new;
end $function$;
