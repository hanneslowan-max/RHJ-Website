CREATE OR REPLACE FUNCTION public.jaga_hapus_sp_ehc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (select 1 from public.ehc_klaim_alokasi where so_id = old.id)
     or exists (select 1 from public.ehc_klaim where so_id = old.id) then
    raise exception 'SP % tidak bisa dihapus: sudah ada klaim EHC atas SP ini. Batalkan SP-nya saja '
                    'supaya riwayat klaimnya tetap ada.', old.no_sp
      using errcode = '23503';
  end if;
  return old;
end $function$;
