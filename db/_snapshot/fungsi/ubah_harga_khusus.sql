CREATE OR REPLACE FUNCTION public.ubah_harga_khusus(p_id bigint, p_harga numeric, p_ehc numeric, p_komisi_pct numeric, p_aktif boolean, p_catatan text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h public.harga_khusus;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh mengubah harga khusus.';
  end if;
  select * into h from public.harga_khusus where id = p_id;
  if not found then raise exception 'Harga khusus tidak ditemukan.'; end if;
  if h.status = 'menunggu' then
    raise exception 'Permintaan ini belum diputus. Setujui atau tolak dulu di antrean GM.';
  end if;
  if p_harga is null or p_harga <= 0 then
    raise exception 'Harga nett harus lebih besar dari nol.';
  end if;
  if p_aktif and (p_komisi_pct is null or p_komisi_pct < 0 or p_komisi_pct > 0.5) then
    raise exception 'Persentase komisi wajib diisi antara 0 dan 50 persen.';
  end if;

  insert into public.harga_khusus_log
    (harga_khusus_id, lama_harga, lama_ehc, lama_pct, lama_status,
     harga_nett, ehc_item, komisi_pct, status, catatan, diubah_oleh)
  values (p_id, h.harga_nett, h.ehc_item, h.komisi_pct, h.status,
          p_harga, coalesce(p_ehc, 0), p_komisi_pct,
          case when p_aktif then 'aktif' else 'nonaktif' end,
          nullif(btrim(coalesce(p_catatan,'')), ''), auth.uid());

  update public.harga_khusus
     set harga_nett = p_harga, ehc_item = coalesce(p_ehc, 0),
         komisi_pct = p_komisi_pct,
         status = case when p_aktif then 'aktif' else 'nonaktif' end,
         catatan_gm = coalesce(nullif(btrim(coalesce(p_catatan,'')), ''), catatan_gm),
         diputus_oleh = auth.uid(), diputus_pada = now()
   where id = p_id;
end $function$;
