CREATE OR REPLACE FUNCTION public.nomor_sp_baru(p_tanggal date DEFAULT CURRENT_DATE)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_no integer; v_th integer; v_bl integer;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengambil nomor Surat Pesanan.' using errcode = '42501';
  end if;
  if not public.setara_owner() or p_tanggal is null then
    p_tanggal := (now() at time zone 'UTC')::date;   -- 133: sama dengan tanggal yang dipaksa saat SP disimpan
  end if;
  v_th := extract(year from p_tanggal)::int;
  v_bl := extract(month from p_tanggal)::int;
  insert into public.sp_counter (tahun, bulan, terakhir) values (v_th, v_bl, 1)
    on conflict (tahun, bulan) do update set terakhir = public.sp_counter.terakhir + 1
    returning terakhir into v_no;
  return public.nomor_sp_angka(v_no) || '/MCE/' || public.bulan_romawi(v_bl)
         || '/' || v_th::text;
end $function$;
