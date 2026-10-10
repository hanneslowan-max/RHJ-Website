CREATE OR REPLACE FUNCTION public.putuskan_harga_khusus(p_id bigint, p_setuju boolean, p_komisi_pct numeric DEFAULT NULL::numeric, p_catatan text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.harga_khusus;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan harga khusus.';
  end if;
  select * into h from public.harga_khusus where id = p_id and status = 'menunggu';
  if not found then raise exception 'Permintaan tidak ditemukan atau sudah diputus.'; end if;
  if p_setuju and (p_komisi_pct is null or p_komisi_pct < 0 or p_komisi_pct > 0.5) then
    raise exception 'Persentase komisi wajib diisi antara 0 dan 50 persen.';
  end if;

  insert into public.harga_khusus_log
    (harga_khusus_id, lama_harga, lama_ehc, lama_pct, lama_status,
     harga_nett, ehc_item, komisi_pct, status, catatan, diubah_oleh)
  values (p_id, h.harga_nett, h.ehc_item, h.komisi_pct, h.status,
          h.harga_nett, h.ehc_item,
          case when p_setuju then p_komisi_pct else h.komisi_pct end,
          case when p_setuju then 'aktif' else 'ditolak' end,
          nullif(btrim(coalesce(p_catatan,'')), ''), auth.uid());

  update public.harga_khusus
     set status = case when p_setuju then 'aktif' else 'ditolak' end,
         komisi_pct = case when p_setuju then p_komisi_pct else komisi_pct end,
         catatan_gm = nullif(btrim(coalesce(p_catatan,'')), ''),
         diputus_oleh = auth.uid(), diputus_pada = now()
   where id = p_id;
end $function$;
