CREATE OR REPLACE FUNCTION public.revisi_no_invoice(p_order bigint, p_nomor text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lama text; baru text;
begin
  if not public.boleh_alur_impor() then
    raise exception 'Anda tidak berwenang merevisi nomor invoice.' using errcode = '42501';
  end if;
  baru := btrim(coalesce(p_nomor, ''));
  if baru = '' then
    raise exception 'Nomor invoice yang baru harus diisi.';
  end if;

  select no_invoice into lama from public.orders where id = p_order;
  if lama is null then raise exception 'Order #% tidak ditemukan.', p_order; end if;
  if lama = baru then
    raise exception 'Nomor invoicenya sudah "%". Tidak ada yang direvisi.', baru;
  end if;

  perform set_config('rhj.revisi', '1', true);
  update public.orders
     set no_invoice = baru,
         -- Hanya yang PERTAMA yang disimpan. Kalau ditimpa tiap revisi,
         -- nomor asli dari owner hilang sesudah revisi kedua — padahal
         -- justru nomor itu yang dipakai mencocokkan pembayaran lama.
         no_invoice_awal = coalesce(no_invoice_awal, lama),
         no_invoice_direvisi_oleh = auth.uid(),
         no_invoice_direvisi_pada = now()
   where id = p_order;
  perform set_config('rhj.revisi', '', true);

  return 'Nomor invoice direvisi dari "' || lama || '" jadi "' || baru
         || '". Nomor lamanya tetap tersimpan.';
end $function$;
