CREATE OR REPLACE FUNCTION public.urutan_status(s text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case s
    when 'Order Diterima'   then 1
    when 'Proses Produksi'  then 2
    when 'Dalam Pengiriman' then 3
    when 'Proses Customs'   then 4
    when 'Sudah Diterima'   then 5
    -- Nama lama tetap dipetakan. Fungsi ini dipakai membandingkan tahap;
    -- kalau nama lama jatuh ke 0, satu baris yang luput terganti akan
    -- dianggap paling awal dan bisa "dinaikkan" ke mana saja.
    when 'Siap Kirim'                    then 2
    when 'Sudah Shipping (On Board)'     then 3
    when 'Dalam Perjalanan (In Transit)' then 3
    when 'Tiba di Pelabuhan'             then 3
    else 0 end
$function$;
