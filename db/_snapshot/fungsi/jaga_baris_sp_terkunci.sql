CREATE OR REPLACE FUNCTION public.jaga_baris_sp_terkunci()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_so bigint; v_no text;
begin
  if public.boleh_ubah_langsung() then return coalesce(new, old); end if;
  if coalesce(current_setting('rhj.usul', true), '') = 'on' then return coalesce(new, old); end if;

  v_so := coalesce(new.so_id, old.so_id);
  select no_sp into v_no from public.sales_orders where id = v_so;

  -- Selama SP-nya masih kosong, barisnya memang sedang dibangun.
  if TG_OP = 'INSERT'
     and (select count(*) from public.sales_order_lines where so_id = v_so) <= 1 then
    return new;
  end if;
  if TG_OP = 'INSERT' then return new; end if;   -- penambahan baris awal

  raise exception
    'Baris Surat Pesanan % tidak bisa diubah langsung. Ajukan perubahannya lewat '
    '"Minta ubah SP" — GM yang memutuskan. Harga dan qty di baris inilah yang '
    'menentukan nilai SP dan komisinya, jadi perubahannya harus terlihat.',
    coalesce(v_no, '(baru)');
end $function$;
