CREATE OR REPLACE FUNCTION public.hitung_kolom_massal(p_jenis text, p_cara text, p_nilai text, p_produk bigint[], p_tempel jsonb DEFAULT NULL::jsonb)
 RETURNS TABLE(product_id bigint, kode text, lama text, baru text, tanda text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare kol text := public.kolom_massal(p_jenis);
begin
  if kol is null then
    raise exception 'Jenis "%" bukan kolom produk.', p_jenis using errcode = '22023';
  end if;
  if not public.boleh_massal(p_jenis) then
    raise exception 'Anda tidak berwenang mengubah kolom % secara massal.', p_jenis
      using errcode = '42501';
  end if;

  return query execute format($f$
    with tempel as (
      select (x->>'product_id')::bigint as pid, nullif(btrim(x->>'nilai'),'') as nilai
        from jsonb_array_elements(coalesce($4, '[]'::jsonb)) x
    ),
    dasar as (
      select p.id, p.kode, nullif(btrim(p.%1$I::text),'') as lama, t.nilai as nilai_tempel
        from public.products p
        left join tempel t on t.pid = p.id
       where p.id = any($3)
    ),
    jadi as (
      select d.id, d.kode, d.lama,
             case $2
               when 'tetap'     then nullif(btrim($1),'')
               -- Tanda minus tunggal berarti "kosongkan baris ini". Diperlukan
               -- karena lewat tempelan, nilai kosong tidak bisa dibedakan dari
               -- baris yang memang tidak diisi — dan dari berkas Excel, sel yang
               -- dibiarkan kosong justru HARUS berarti "jangan diubah".
               -- Aman dipakai sebagai penanda: '-' bukan nilai sah untuk bracket,
               -- bahan, maupun ukuran, dan tidak masuk akal sebagai nama kelompok.
               when 'tempel'    then case when d.nilai_tempel = '-' then null
                                          else d.nilai_tempel end
               when 'kosongkan' then null
             end as baru,
             ($2 = 'kosongkan' or ($2 = 'tempel' and d.nilai_tempel = '-')) as mengosongkan,
             ($2 = 'tempel' and d.nilai_tempel is null) as tak_ditempel
        from dasar d
    )
    select j.id, j.kode, j.lama, j.baru,
           case
             when j.tak_ditempel                              then 'lewat'
             when j.baru is null and not j.mengosongkan        then 'lewat'
             when not public.nilai_massal_sah($5, j.baru)      then 'tak_sah'
             when j.baru is not distinct from j.lama           then 'sama'
             when j.lama is null                               then 'isi'
             else 'timpa'
           end
      from jadi j
     order by j.kode
  $f$, kol) using p_nilai, p_cara, p_produk, p_tempel, p_jenis;
end $function$;
