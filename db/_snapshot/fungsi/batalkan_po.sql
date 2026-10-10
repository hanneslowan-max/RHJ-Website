CREATE OR REPLACE FUNCTION public.batalkan_po(p_id bigint, p_alasan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; n_sp int;
begin
  if not public.boleh_input_po() then
    raise exception 'Peran Anda tidak boleh membatalkan PO.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Alasan pembatalan wajib diisi. Nomor PO yang hilang tanpa keterangan '
                    'akan ditanyakan lagi berbulan-bulan kemudian.' using errcode = '22023';
  end if;
  select * into v from public.purchase_orders where id = p_id;
  if v.id is null then
    raise exception 'PO #% tidak ditemukan.', p_id using errcode = 'P0002';
  end if;
  if public.peran_saya() = 'sales'
     and v.sales_rep_id is distinct from public.sales_rep_saya() then
    raise exception 'PO ini bukan milik Anda. Hanya sales yang memegangnya, '
                    'atau owner/GM/staff/Vonny, yang boleh membatalkannya.'
      using errcode = '42501';
  end if;
  if v.batal then
    raise exception 'PO % sudah dibatalkan.', v.no_po using errcode = '22023';
  end if;

  select count(*) into n_sp from public.sales_orders s where s.po_id = p_id and not s.batal;
  if n_sp > 0 then
    raise exception 'PO % sudah punya % Surat Pesanan yang masih berlaku. Batalkan Surat '
                    'Pesanannya dulu — kalau tidak, SP-nya menggantung pada PO yang secara '
                    'resmi tidak pernah ada.', v.no_po, n_sp using errcode = '23503';
  end if;

  update public.purchase_orders
     set batal = true, alasan_batal = btrim(p_alasan),
         dibatalkan_pada = now(), dibatalkan_oleh = auth.uid(),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_id;

  return 'PO ' || v.no_po || ' dibatalkan.';
end $function$;
