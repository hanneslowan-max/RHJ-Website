CREATE OR REPLACE FUNCTION public.batalkan_lead(p_lead bigint, p_alasan text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- gerbang-55: pemilik diperiksa sebelum apa pun dikerjakan
  if not public.boleh_ubah_lead(p_lead) then raise exception 'Lead ini bukan milik Anda. Sales hanya bisa membatalkan lead yang dipegangnya sendiri; kalau lead ini memang salah, mintalah owner, GM, atau staff yang membatalkannya.' using errcode = '42501'; end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Alasan batal wajib diisi.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.leads where id = p_lead) then
    raise exception 'Lead tidak ditemukan.' using errcode = 'P0002';
  end if;
  insert into public.lead_events (lead_id, jenis, tanggal, keterangan, dibuat_oleh)
  values (p_lead, 'batal', current_date, btrim(p_alasan), auth.uid());
  perform set_config('rhj.crm', '1', true);
  update public.leads set alasan_batal = btrim(p_alasan) where id = p_lead;
  perform set_config('rhj.crm', '', true);
end $function$;
