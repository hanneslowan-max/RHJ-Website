CREATE OR REPLACE FUNCTION public.salin_rekening_klaim_komisi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.komisi_klaim_rekening (klaim_id, sales_rep_id, bank, no_rekening, atas_nama)
  values (new.id, new.sales_rep_id, new.bank, new.no_rekening, new.atas_nama)
  on conflict (klaim_id) do update
    set sales_rep_id = excluded.sales_rep_id, bank = excluded.bank,
        no_rekening = excluded.no_rekening, atas_nama = excluded.atas_nama;
  return null;
end $function$;
