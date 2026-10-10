CREATE OR REPLACE FUNCTION public.jaga_cash_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.cash_ok is distinct from old.cash_ok then
    if public.peran_saya() not in ('owner','gm','finance','ichi') then
      raise exception 'Hanya finance, Ichi, GM, atau owner yang boleh mencocokkan penjualan cash.';
    end if;
    new.cash_oleh := auth.uid();
    new.cash_pada := now();
  end if;
  if new.cash_minta is distinct from old.cash_minta
     and old.cash_ok is not null
     and public.peran_saya() not in ('owner','gm','finance','ichi') then
    raise exception 'Penjualan ini sudah dicocokkan finance. Klaim cash-nya tidak bisa diubah lagi.';
  end if;
  return new;
end $function$;
