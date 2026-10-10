CREATE OR REPLACE FUNCTION public.jaga_tahan_hitam_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;   -- 139x: SP batal tidak dikecualikan
  if new.kepada is not distinct from old.kepada and new.telp is not distinct from old.telp
     and new.customer_id is not distinct from old.customer_id and new.po_id is not distinct from old.po_id then
    return new;
  end if;
  if public.sp_pelanggan_hitam(old.customer_id, old.po_id, old.kepada, old.telp) is not null then
    raise exception 'Surat Pesanan % ditahan karena pelanggannya (atau nama/No. HP-nya) cocok dengan pelanggan daftar '
                    'hitam — Kepada, No. HP, pelanggan, dan PO-nya hanya diubah owner/GM (Minta ubah SP yang disetujui '
                    'GM, atau tautkan oleh owner/GM), juga selama SP dibatalkan.', coalesce(old.no_sp, '(baru)')
      using errcode = '23514';
  end if;
  return new;
end $function$;
