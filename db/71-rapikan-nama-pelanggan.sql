-- Berkas 71 (#20): rapikan nama pelanggan — PT/CV/UD/PD ke depan + Title Case.
-- Preview & reversibel. Backup ke customers.nama_lama (diisi hanya saat pertama dirapikan).
--
-- Fungsi:
--   rhj_nama_rapi(text)                 : normalisasi 1 nama (immutable, murni).
--     - Entitas (PT/CV/UD/PD) dipindah ke depan HANYA bila ada di kata pertama/terakhir.
--     - initcap untuk Title Case; token entitas di tengah dikembalikan kapital (\yPt\y->PT).
--     - huruf setelah angka dikapitalkan (3p->3P) — lihat berkas 71b (revisi fungsi ini).
--   pratinjau_nama_pelanggan()          : RETURNS TABLE(id,nama_kini,nama_baru) baris yg berubah.
--   terapkan_rapi_nama(p_ids bigint[])  : set nama=rapi, backup nama_lama sekali. null=semua.
--   pulihkan_nama_pelanggan(p_ids ...)  : nama=nama_lama, kosongkan backup. null=semua.
-- Ketiganya SECURITY DEFINER + gerbang boleh_konfirmasi_kirim() (owner/gm/vonny).
-- Trigger customers_jaga_sales hanya cek sales_rep_id → update nama-saja tidak diblok.
-- Tidak ada unique constraint pada nama → normalisasi massal tak gagal karena tabrakan.
--
-- FE (index.html): tombol "🧹 Rapikan Nama" di panel Pelanggan (owner/gm/vonny) → laci
--   pratinjau (Sebelum→Sesudah) + tombol Terapkan / Pulihkan.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. BELUM diterapkan ke data (preview saja
--   sampai Hannes menekan Terapkan). Belum ke produksi.
-- Badan final fungsi = seperti diterapkan via apply_migration berkas71 + berkas71b.

alter table public.customers add column if not exists nama_lama text;

create or replace function public.rhj_nama_rapi(p text)
returns text language plpgsql immutable as $$
declare
  s text; words text[]; n int; ent text := null; rest text[]; rest_str text;
  ents text[] := array['PT','CV','UD','PD'];
begin
  if p is null then return null; end if;
  s := btrim(regexp_replace(p, '\s+', ' ', 'g'));
  if s = '' then return p; end if;
  words := regexp_split_to_array(s, ' ');
  n := array_length(words, 1);
  if upper(regexp_replace(words[n], '[^[:alnum:]]', '', 'g')) = any(ents) then
    ent := upper(regexp_replace(words[n], '[^[:alnum:]]', '', 'g'));
    rest := words[1:n-1];
  elsif upper(regexp_replace(words[1], '[^[:alnum:]]', '', 'g')) = any(ents) then
    ent := upper(regexp_replace(words[1], '[^[:alnum:]]', '', 'g'));
    rest := words[2:n];
  else
    rest := words;
  end if;
  rest_str := btrim(array_to_string(rest, ' '));
  rest_str := btrim(rest_str, ' ,;.-');
  s := initcap(rest_str);
  s := regexp_replace(s, '\yPt\y', 'PT', 'g');
  s := regexp_replace(s, '\yCv\y', 'CV', 'g');
  s := regexp_replace(s, '\yUd\y', 'UD', 'g');
  s := regexp_replace(s, '\yPd\y', 'PD', 'g');
  while s ~ '[0-9][a-z]' loop
    s := regexp_replace(s, '([0-9])([a-z])', '\1' || upper((regexp_match(s, '[0-9]([a-z])'))[1]), '');
  end loop;
  if ent is not null then
    s := ent || case when s <> '' then ' ' || s else '' end;
  end if;
  return btrim(s);
end $$;

create or replace function public.pratinjau_nama_pelanggan()
returns table(id bigint, nama_kini text, nama_baru text)
language plpgsql security definer set search_path=public stable as $$
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh merapikan nama pelanggan.' using errcode='42501';
  end if;
  return query
    select c.id, c.nama, public.rhj_nama_rapi(c.nama)
    from public.customers c
    where public.rhj_nama_rapi(c.nama) is distinct from c.nama
    order by c.nama;
end $$;

create or replace function public.terapkan_rapi_nama(p_ids bigint[] default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_n integer;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh merapikan nama pelanggan.' using errcode='42501';
  end if;
  with upd as (
    update public.customers c
      set nama_lama = coalesce(c.nama_lama, c.nama),
          nama      = public.rhj_nama_rapi(c.nama)
    where public.rhj_nama_rapi(c.nama) is distinct from c.nama
      and (p_ids is null or c.id = any(p_ids))
    returning 1
  )
  select count(*) into v_n from upd;
  return v_n;
end $$;

create or replace function public.pulihkan_nama_pelanggan(p_ids bigint[] default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_n integer;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh memulihkan nama pelanggan.' using errcode='42501';
  end if;
  with upd as (
    update public.customers c
      set nama = c.nama_lama, nama_lama = null
    where c.nama_lama is not null
      and (p_ids is null or c.id = any(p_ids))
    returning 1
  )
  select count(*) into v_n from upd;
  return v_n;
end $$;

grant execute on function public.pratinjau_nama_pelanggan() to authenticated;
grant execute on function public.terapkan_rapi_nama(bigint[]) to authenticated;
grant execute on function public.pulihkan_nama_pelanggan(bigint[]) to authenticated;
grant execute on function public.rhj_nama_rapi(text) to authenticated;
