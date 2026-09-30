-- ═══════════════════════════════════════════════════════════════════════
-- 111 · #49 Sales boleh MELIHAT pelanggan sales lain (baca saja)
--
-- RLS customers tetap: sales hanya membaca pelanggan miliknya + yang belum
-- bertuan, dan tetap tidak bisa memakai pelanggan sales lain di PO/penawaran/SP
-- (trigger & RLS yang sudah ada). Yang ditambahkan hanya satu RPC baca yang
-- sengaja miskin kolom: nama perusahaan, cabang, industri, dan nama sales
-- pemegang — TANPA id, HP, telp, alamat (lokasi), PIC, maupun transaksi.
-- Tabel customers tidak punya kolom kota; "cabang" yang dipakai (alamat =
-- lokasi tidak dibuka).
--
-- Tidak ada data yang diubah.
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.pelanggan_sales_lain(p_cari text default null, p_dari int default 0, p_jumlah int default 50)
returns table (nama text, cabang text, industri text, sales_nama text, total bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  v_saya bigint;
  v_pola text;
  v_dari int := greatest(coalesce(p_dari, 0), 0);
  v_jml  int := least(greatest(coalesce(p_jumlah, 50), 1), 200);
begin
  if public.peran_saya() <> 'sales' then return; end if;   -- peran lain sudah bisa membaca semuanya lewat RLS
  v_saya := public.sales_rep_saya();
  if v_saya is null then return; end if;
  -- kata alfanumerik tanpa badan usaha, dicocokkan ke nama & nama_lama (sama dengan cek_pemilik_pelanggan)
  select string_agg(k, '%' order by n) into v_pola
    from regexp_split_to_table(btrim(regexp_replace(lower(coalesce(p_cari, '')), '[^[:alnum:]]+', ' ', 'g')), ' ')
         with ordinality as s(k, n)
   where k <> '' and k not in ('pt','cv','ud','pd','tb','tbk','toko');
  v_pola := case when coalesce(v_pola, '') = '' then null else '%' || v_pola || '%' end;
  return query
    select c.nama, c.cabang, c.industri,
           sr.nama || case when sr.aktif then '' else ' (nonaktif)' end,
           count(*) over ()
      from public.customers c
      join public.sales_reps sr on sr.id = c.sales_rep_id
     where c.sales_rep_id <> v_saya
       and (v_pola is null
            or regexp_replace(lower(c.nama), '[^[:alnum:]]+', ' ', 'g') like v_pola
            or regexp_replace(lower(coalesce(c.nama_lama, '')), '[^[:alnum:]]+', ' ', 'g') like v_pola)
     order by c.nama_urut, c.id
     offset v_dari limit v_jml;
end $$;
revoke all on function public.pelanggan_sales_lain(text, int, int) from public, anon;
grant execute on function public.pelanggan_sales_lain(text, int, int) to authenticated;
