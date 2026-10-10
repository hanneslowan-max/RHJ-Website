CREATE OR REPLACE FUNCTION public.batalkan_massal(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j text;
begin
  select jenis into j from public.edit_massal where id = p_id;
  if j is null then
    raise exception 'Edit massal #% tidak ditemukan.', p_id using errcode = 'P0002';
  end if;
  if j in ('harga','hpp') then return public.batalkan_edit_massal(p_id);
  else                         return public.batalkan_kolom_massal(p_id);
  end if;
end $function$;
