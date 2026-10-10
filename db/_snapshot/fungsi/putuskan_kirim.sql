CREATE OR REPLACE FUNCTION public.putuskan_kirim(p_so bigint, p_boleh boolean, p_alasan text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh mengizinkan pengiriman untuk '
                    'pelanggan yang perlu dikonfirmasi.' using errcode = '42501';
  end if;
  select * into v from public.sales_orders where id = p_so;
  if v.id is null then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002';
  end if;
  if v.batal then
    raise exception 'Surat Pesanan % sudah dibatalkan.', v.no_sp using errcode = '22023';
  end if;
  if p_boleh is false and coalesce(btrim(p_alasan),'') = '' then
    raise exception 'Menahan pengiriman wajib beralasan. Sales-nya harus tahu apa yang '
                    'perlu dibereskan.' using errcode = '22023';
  end if;

  update public.sales_orders
     set kirim_ok = p_boleh, kirim_ok_oleh = auth.uid(), kirim_ok_pada = now(),
         kirim_alasan = nullif(btrim(coalesce(p_alasan,'')), ''),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_so;

  return 'Surat Pesanan ' || v.no_sp || (case when p_boleh then ' boleh dikirim.'
                                              else ' DITAHAN.' end)
         || case when coalesce(btrim(p_alasan),'') <> '' then ' (' || btrim(p_alasan) || ')' else '' end;
end $function$;
