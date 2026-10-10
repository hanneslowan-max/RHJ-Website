CREATE OR REPLACE FUNCTION public.hitung_edit_massal(p_jenis text, p_cara text, p_nilai numeric, p_pembulatan integer, p_produk bigint[], p_tempel jsonb DEFAULT NULL::jsonb)
 RETURNS TABLE(product_id bigint, kode text, lama numeric, baru numeric, hpp numeric, ubah_persen numeric, tanda text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bulat int := greatest(coalesce(p_pembulatan, 0), 0);
begin
  if not public.boleh_massal(p_jenis) then
    raise exception 'Anda tidak berwenang mengubah % secara massal.',
      case p_jenis when 'harga' then 'harga jual' else 'HPP' end using errcode = '42501';
  end if;

  return query
  with tempel as (
    select (x->>'product_id')::bigint as pid, (x->>'nilai')::numeric as nilai
      from jsonb_array_elements(coalesce(p_tempel, '[]'::jsonb)) x
  ),
  dasar as (
    select p.id, p.kode,
           case when p_jenis = 'harga' then public.harga_berlaku_hitung(p.id)
                                       else public.hpp_berlaku(p.id) end as lama,
           public.hpp_berlaku(p.id) as hpp_kini,
           t.nilai as nilai_tempel
      from public.products p
      left join tempel t on t.pid = p.id
     where p.id = any(p_produk)
  ),
  dihitung as (
    select d.id, d.kode, d.lama, d.hpp_kini,
           case p_cara
             when 'tetap'  then p_nilai
             when 'persen' then case when d.lama is null then null
                                     else d.lama * (1 + p_nilai / 100.0) end
             when 'rupiah' then case when d.lama is null then null
                                     else d.lama + p_nilai end
             when 'tempel' then d.nilai_tempel
           end as mentah
      from dasar d
  ),
  jadi as (
    select h.id, h.kode, h.lama, h.hpp_kini,
           case when h.mentah is null then null
                when bulat > 0 then greatest(round(h.mentah / bulat) * bulat, 0)
                else greatest(round(h.mentah, 2), 0) end as baru
      from dihitung h
  )
  select j.id, j.kode, j.lama, j.baru, j.hpp_kini,
         case when j.lama is null or j.lama = 0 or j.baru is null then null
              else round((j.baru - j.lama) / j.lama * 100, 1) end,
         case
           when j.baru is null                              then 'lewat'
           when j.lama is null                              then 'baru'
           when j.baru = j.lama                             then 'sama'
           -- di bawah HPP diperiksa lebih dulu: satu baris bisa sekaligus
           -- melonjak dan jatuh di bawah HPP, dan yang kedua itu kesalahan
           -- dagang yang nyata, sementara lonjakan cuma "yakin segini?"
           when p_jenis = 'harga' and j.hpp_kini is not null
            and j.baru < j.hpp_kini                         then 'di_bawah_hpp'
           when j.lama > 0
            and abs(j.baru - j.lama) / j.lama > 0.5         then 'lonjakan'
           else 'ok'
         end
    from jadi j
   order by j.kode;
end $function$;
