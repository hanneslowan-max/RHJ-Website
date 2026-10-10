CREATE OR REPLACE FUNCTION public.atur_anggota_grup(p_customer bigint, p_grup bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lama bigint; v_nama text; v_grup_lama text;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh mengatur anggota grup pelanggan.' using errcode = '42501';
  end if;
  select c.grup_id, c.nama into v_lama, v_nama from public.customers c where c.id = p_customer for update;
  if v_nama is null then raise exception 'Pelanggan #% tidak ditemukan.', p_customer using errcode = 'P0002'; end if;
  if p_grup is not null then
    if not exists (select 1 from public.customer_groups g where g.id = p_grup) then
      raise exception 'Grup #% tidak ditemukan.', p_grup using errcode = 'P0002';
    end if;
    if v_lama is not null and v_lama <> p_grup then
      select g.nama into v_grup_lama from public.customer_groups g where g.id = v_lama;
      raise exception '% sudah anggota grup "%" — keluarkan dulu dari grup itu.', v_nama, v_grup_lama using errcode = '23505';
    end if;
  end if;
  update public.customers set grup_id = p_grup where id = p_customer and grup_id is distinct from p_grup;
end $function$;
