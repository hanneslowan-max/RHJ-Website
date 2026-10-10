CREATE OR REPLACE FUNCTION public.izinkan_invoice_tanpa_po(p_so bigint, p_alasan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  if public.peran_saya() not in ('owner','gm') then
    raise exception 'Hanya owner atau GM yang boleh mengizinkan invoice tanpa PO.'
      using errcode = '42501';
  end if;
  if coalesce(btrim(p_alasan),'') = '' then
    raise exception 'Pengecualian ini wajib beralasan. Alasannya yang membedakannya dari '
                    'kelalaian saat diperiksa belakangan.' using errcode = '22023';
  end if;
  select * into v from public.sales_orders where id = p_so;
  if v.id is null then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002';
  end if;
  if v.po_id is not null then
    raise exception 'Surat Pesanan % sudah punya PO — tidak ada yang perlu dikecualikan.',
                    v.no_sp using errcode = '22023';
  end if;

  perform set_config('rhj.tanpa_po', '1', true);
  update public.sales_orders
     set tanpa_po_ok = true, tanpa_po_alasan = btrim(p_alasan),
         tanpa_po_oleh = auth.uid(), tanpa_po_pada = now(),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_so;
  perform set_config('rhj.tanpa_po', '', true);

  return 'Surat Pesanan ' || v.no_sp || ' boleh ditagih tanpa PO. (' || btrim(p_alasan) || ')';
end $function$;
