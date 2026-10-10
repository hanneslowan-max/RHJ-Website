CREATE OR REPLACE FUNCTION public.isi_judul_grup_penawaran()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.kepada_grup is not null then
    new.kepada_grup := public.judul_grup_pelanggan(new.customer_id);
  end if;
  return new;
end $function$;
