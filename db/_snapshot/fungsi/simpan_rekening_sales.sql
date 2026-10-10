CREATE OR REPLACE FUNCTION public.simpan_rekening_sales(p_rep bigint, p_bank text, p_rek text, p_atas_nama text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v public.sales_rep_rekening;
begin
  if public.peran_saya() not in ('owner','gm','finance') then
    raise exception 'Rekening sales hanya boleh diisi finance, GM, atau owner.';
  end if;
  if coalesce(btrim(p_bank), '') = '' or coalesce(btrim(p_rek), '') = '' then
    raise exception 'Bank dan nomor rekening harus diisi berdua.';
  end if;
  if not exists (select 1 from public.sales_reps where id = p_rep) then
    raise exception 'Sales tidak ditemukan.';
  end if;

  select * into v from public.sales_rep_rekening where sales_rep_id = p_rep;

  insert into public.sales_rep_rekening_log
    (sales_rep_id, lama_bank, lama_no_rekening, lama_atas_nama,
     bank, no_rekening, atas_nama, diubah_oleh)
  values (p_rep, v.bank, v.no_rekening, v.atas_nama,
          btrim(p_bank), btrim(p_rek), nullif(btrim(p_atas_nama), ''), auth.uid());

  insert into public.sales_rep_rekening
    (sales_rep_id, bank, no_rekening, atas_nama, diubah_pada, diubah_oleh)
  values (p_rep, btrim(p_bank), btrim(p_rek), nullif(btrim(p_atas_nama), ''), now(), auth.uid())
  on conflict (sales_rep_id) do update
    set bank = excluded.bank, no_rekening = excluded.no_rekening,
        atas_nama = excluded.atas_nama, diubah_pada = now(), diubah_oleh = auth.uid();
  return p_rep;
end $function$;
