CREATE OR REPLACE FUNCTION public.sp_terbaca(p_rep bigint, p_dibuat_oleh uuid, p_batal boolean, p_no_sj text, p_vonny_ok boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- cermin RLS so_baca (berkas 83): ubah bersama-sama
  select coalesce(
           ((select public.peran_saya()) = 'sales' and p_rep = (select public.sales_rep_saya()))
           or case when not p_batal and p_no_sj is null and not coalesce(p_vonny_ok, false)
                   then (select public.peran_saya()) in ('owner','gm','vonny')
                        or (p_dibuat_oleh = (select auth.uid()) and (select public.boleh_alur_jual()))
                   else (select public.boleh_lihat_semua_jual())
              end, false)
$function$;
