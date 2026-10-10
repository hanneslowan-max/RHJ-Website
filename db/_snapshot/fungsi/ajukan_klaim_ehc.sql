CREATE OR REPLACE FUNCTION public.ajukan_klaim_ehc(p_so bigint, p_pic bigint, p_nominal numeric, p_tanggal date, p_berkas jsonb, p_cara_bayar text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  raise exception 'Klaim EHC sekarang diajukan lewat form baru (simpan_klaim_ehc): bisa memakai beberapa SP, '
                  'wajib lampiran. Muat ulang halaman.' using errcode = '0A000';
end $function$;
