-- Berkas 101 (#21): konteks HPP untuk keputusan GM lengkap.
--   - harga/telat/ehc_dini: baris SP batal disaring, qty = qty efektif (qty − qty_batal, #18).
--   - ehc_dini (klaim EHC dini) dan ubah (usulan ubah PO/SP: versi sebelum & sesudah) kini ikut punya konteks HPP.
--   - Kolom baru (aditif di ujung): harga_jual = nett + EHC (dibayar pelanggan sebelum PPN),
--     margin_kotor = harga_jual − HPP (sebelum EHC dikembalikan ke PIC), margin_pct = (nett − HPP)/nett × 100,
--     margin_total = margin × qty efektif, versi ('sebelum'|'sesudah', untuk 'ubah'), urut.
--   - margin = nett − HPP = margin SESUDAH EHC (EHC dikembalikan ke PIC, yang tinggal di RHJ = nett).
--     ASUMSI: nett tidak memuat EHC (baris SP = (nett + EHC) × qty). Bila Hannes memaknai lain, cukup ubah
--     ekspresi margin. margin kini NULL bila HPP kosong (dulu 0-coalesce → nett penuh; FE menampilkan "—").
--   - PO (usul ubah jenis 'po'): harga_jual = harga efektif per unit sesudah diskon; margin_kotor = harga_jual − HPP;
--     kolom nett/EHC/margin/pct/total NULL (PO tidak memuat EHC). Baris set: nama set, HPP NULL.
--   - Tanpa round() di mana pun (#12).
-- Signature hasil berubah → DROP + CREATE (tidak ada objek yang bergantung). Argumen sama.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 2026-09-29 lewat migrasi gm_konteks_hpp_lengkap. Belum ke produksi.
-- Data: tidak ada yang diubah.

drop function if exists public.gm_konteks_keputusan(text, bigint);
create function public.gm_konteks_keputusan(p_jenis text, p_ref bigint)
returns table(kode text, qty numeric, harga_nett numeric, ehc numeric, hpp numeric, margin numeric,
              harga_jual numeric, margin_kotor numeric, margin_pct numeric, margin_total numeric,
              versi text, urut integer)
language plpgsql stable security definer
set search_path = public
as $fn$
#variable_conflict use_column
declare
  u   public.usul_ubah%rowtype;
  v_tgl date;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner atau GM yang boleh melihat konteks HPP keputusan.' using errcode = '42501';
  end if;

  if p_jenis in ('harga','telat','ehc_dini') then
    return query
      with b as (
        select l.urut as u_urut,
               coalesce(p.kode, nullif(l.deskripsi,''), '-') as u_kode,
               greatest(l.qty - coalesce(l.qty_batal, 0), 0) as u_qty,   -- #18: qty efektif
               l.harga_nett as u_nett,
               coalesce(l.ehc_item, 0) as u_ehc,
               public.hpp_berlaku(l.product_id, s.tanggal) as u_hpp
          from public.sales_order_lines l
          join public.sales_orders s on s.id = l.so_id
          left join public.products p on p.id = l.product_id
         where l.so_id = p_ref and l.jenis = 'barang'
           and not coalesce(l.batal, false))
      select b.u_kode, b.u_qty, b.u_nett, b.u_ehc, b.u_hpp,
             b.u_nett - b.u_hpp,
             b.u_nett + b.u_ehc,
             b.u_nett + b.u_ehc - b.u_hpp,
             case when b.u_hpp is null or b.u_nett = 0 then null
                  else (b.u_nett - b.u_hpp) / b.u_nett * 100 end,
             (b.u_nett - b.u_hpp) * b.u_qty,
             null::text, b.u_urut
        from b
       where b.u_qty > 0
       order by b.u_urut;

  elsif p_jenis = 'harga_khusus' then
    select coalesce((select s2.tanggal from public.sales_orders s2 where s2.id = h.so_id), current_date)
      into v_tgl from public.harga_khusus h where h.id = p_ref;
    return query
      select coalesce(p.kode, '-'), null::numeric, h.harga_nett, coalesce(h.ehc_item, 0), x.hpp,
             h.harga_nett - x.hpp,
             h.harga_nett + coalesce(h.ehc_item, 0),
             h.harga_nett + coalesce(h.ehc_item, 0) - x.hpp,
             case when x.hpp is null or h.harga_nett = 0 then null
                  else (h.harga_nett - x.hpp) / h.harga_nett * 100 end,
             null::numeric, null::text, null::integer
        from public.harga_khusus h
        left join public.products p on p.id = h.product_id
        cross join lateral (select public.hpp_berlaku(h.product_id, v_tgl) as hpp) x
       where h.id = p_ref;

  elsif p_jenis = 'ubah' then
    select * into u from public.usul_ubah where id = p_ref;
    if u.id is null then return; end if;
    v_tgl := coalesce(nullif(u.nilai_lama #>> '{kepala,tanggal}', '')::date, current_date);

    if u.jenis = 'sp' then
      return query
        with b as (
          select v.versi as u_versi, (x->>'urut')::integer as u_urut,
                 nullif(x->>'product_id','')::bigint as u_pid, x->>'deskripsi' as u_desk,
                 greatest(coalesce(nullif(x->>'qty','')::numeric, 0)
                          - coalesce(nullif(x->>'qty_batal','')::numeric, 0), 0) as u_qty,   -- #18
                 coalesce(nullif(x->>'harga_nett','')::numeric, 0) as u_nett,
                 coalesce(nullif(x->>'ehc_item','')::numeric, 0) as u_ehc
            from (values ('sebelum', u.nilai_lama->'baris'), ('sesudah', u.nilai_baru->'baris')) v(versi, arr)
            cross join lateral jsonb_array_elements(coalesce(v.arr, '[]'::jsonb)) x
           where coalesce(x->>'jenis', 'barang') = 'barang'
             and not coalesce((x->>'batal')::boolean, false))
        select coalesce(p.kode, nullif(b.u_desk,''), '-'), b.u_qty, b.u_nett, b.u_ehc, h.hpp,
               b.u_nett - h.hpp,
               b.u_nett + b.u_ehc,
               b.u_nett + b.u_ehc - h.hpp,
               case when h.hpp is null or b.u_nett = 0 then null
                    else (b.u_nett - h.hpp) / b.u_nett * 100 end,
               (b.u_nett - h.hpp) * b.u_qty,
               b.u_versi, b.u_urut
          from b
          left join public.products p on p.id = b.u_pid
          cross join lateral (select public.hpp_berlaku(b.u_pid, v_tgl) as hpp) h
         order by b.u_urut, b.u_versi;
    else
      return query
        with b as (
          select v.versi as u_versi, (x->>'urut')::integer as u_urut,
                 nullif(x->>'product_id','')::bigint as u_pid,
                 nullif(x->>'set_id','')::bigint as u_set, x->>'deskripsi' as u_desk,
                 coalesce(nullif(x->>'qty','')::numeric, 0) as u_qty,
                 coalesce(nullif(x->>'harga','')::numeric, 0) as u_harga,
                 coalesce(nullif(x->>'diskon','')::numeric, 0) as u_disk,
                 coalesce(x->>'diskon_tipe', 'rp') as u_dtipe
            from (values ('sebelum', u.nilai_lama->'baris'), ('sesudah', u.nilai_baru->'baris')) v(versi, arr)
            cross join lateral jsonb_array_elements(coalesce(v.arr, '[]'::jsonb)) x
           where coalesce(x->>'jenis', 'barang') = 'barang'),
        e as (
          select b.*, case when b.u_qty = 0 then null
                           when b.u_dtipe = 'persen' then b.u_harga * (1 - b.u_disk / 100)
                           else b.u_harga - b.u_disk / b.u_qty end as u_eff
            from b)
        select coalesce(p.kode, ps.nama, nullif(e.u_desk,''), '-'), e.u_qty, null::numeric, null::numeric, h.hpp,
               null::numeric,
               e.u_eff,
               e.u_eff - h.hpp,
               null::numeric, null::numeric,
               e.u_versi, e.u_urut
          from e
          left join public.products p on p.id = e.u_pid
          left join public.product_sets ps on ps.id = e.u_set
          cross join lateral (select public.hpp_berlaku(e.u_pid, v_tgl) as hpp) h
         order by e.u_urut, e.u_versi;
    end if;
  end if;
end
$fn$;
revoke all on function public.gm_konteks_keputusan(text, bigint) from public, anon;
grant execute on function public.gm_konteks_keputusan(text, bigint) to authenticated;


-- ROLLBACK (definisi sebelum berkas ini, dari berkas 98):
-- drop function public.gm_konteks_keputusan(text, bigint);
-- create or replace function public.gm_konteks_keputusan(p_jenis text, p_ref bigint)
--  returns table(kode text, qty numeric, harga_nett numeric, ehc numeric, hpp numeric, margin numeric)
--  language plpgsql
--  stable security definer
--  set search_path to 'public'
-- as $function$
-- begin
--   if not public.setara_owner() then
--     raise exception 'Hanya owner atau GM yang boleh melihat konteks HPP keputusan.' using errcode='42501';
--   end if;
--   if p_jenis in ('harga','telat') then
--     return query
--       select coalesce(p.kode,'-'), l.qty - l.qty_batal, l.harga_nett, l.ehc_item,   -- #18: qty efektif
--              public.hpp_berlaku(l.product_id, s.tanggal),
--              (l.harga_nett - coalesce(public.hpp_berlaku(l.product_id, s.tanggal),0))
--       from public.sales_order_lines l
--       join public.sales_orders s on s.id = l.so_id
--       left join public.products p on p.id = l.product_id
--       where l.so_id = p_ref and l.jenis = 'barang' and not l.batal and l.qty - l.qty_batal > 0
--       order by l.urut;
--   elsif p_jenis = 'harga_khusus' then
--     return query
--       select coalesce(p.kode,'-'), null::numeric, h.harga_nett, h.ehc_item,
--              public.hpp_berlaku(h.product_id, coalesce((select s2.tanggal from public.sales_orders s2 where s2.id = h.so_id), current_date)),
--              (h.harga_nett - coalesce(public.hpp_berlaku(h.product_id, coalesce((select s2.tanggal from public.sales_orders s2 where s2.id = h.so_id), current_date)),0))
--       from public.harga_khusus h
--       left join public.products p on p.id = h.product_id
--       where h.id = p_ref;
--   end if;
-- end $function$;
-- revoke all on function public.gm_konteks_keputusan(text,bigint) from public, anon;
-- grant execute on function public.gm_konteks_keputusan(text,bigint) to authenticated;
