CREATE OR REPLACE FUNCTION public.simpan_grup_pelanggan(p_id bigint, p_nama text, p_nama_dokumen text, p_catatan text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_nama text := btrim(coalesce(p_nama, '')); v_dok text := nullif(btrim(coalesce(p_nama_dokumen, '')), '');
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh mengatur grup pelanggan.' using errcode = '42501';
  end if;
  if char_length(v_nama) < 2 or char_length(v_nama) > 120 then
    raise exception 'Nama grup wajib diisi (2–120 huruf).';
  end if;
  if v_dok is not null and (char_length(v_dok) < 2 or char_length(v_dok) > 160) then
    raise exception 'Nama induk di dokumen 2–160 huruf, atau kosongkan (memakai nama grup).';
  end if;
  begin
    if p_id is null then
      insert into public.customer_groups (nama, nama_dokumen, catatan)
      values (v_nama, v_dok, nullif(btrim(coalesce(p_catatan, '')), ''))
      returning id into v_id;
    else
      update public.customer_groups
         set nama = v_nama, nama_dokumen = v_dok, catatan = nullif(btrim(coalesce(p_catatan, '')), '')
       where id = p_id
      returning id into v_id;
      if v_id is null then raise exception 'Grup #% tidak ditemukan.', p_id using errcode = 'P0002'; end if;
    end if;
  exception when unique_violation then
    raise exception 'Grup bernama "%" sudah ada.', v_nama using errcode = '23505';
  end;
  return v_id;
end $function$;
