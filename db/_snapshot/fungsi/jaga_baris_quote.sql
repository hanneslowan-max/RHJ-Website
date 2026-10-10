CREATE OR REPLACE FUNCTION public.jaga_baris_quote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_kode text; v_teks text; v_sat text; v_set text;
begin
  if auth.uid() is null then return new; end if;   -- migrasi / service role
  if not exists (select 1 from public.quotes q
                  where q.id = new.quote_id and q.dibuat_pada = now() and q.dibuat_oleh = auth.uid()) then
    raise exception 'Baris penawaran hanya dibuat bersama penawarannya (tombol Simpan penawaran). Penawaran yang sudah '
                    'tersimpan tidak bisa ditambah barisnya — buat penawaran baru dari penawaran itu bila perlu diubah.';
  end if;
  if new.product_id is null and new.set_id is null and new.set_komponen is null then
    raise exception 'Baris penawaran harus menunjuk barang di master, set, atau set yang dirakit di baris itu. Barang '
                    'yang belum ada di master dipakai lewat "+ item baru" (usulan) — baris teks bebas tidak disimpan.';
  end if;
  -- 137b: nama barang & satuan dari master, bukan kiriman klien (spesifikasi tetap bebas)
  if new.set_komponen is not null then
    new.deskripsi := '—';                       -- quote_lines_set_inline mengisi label_set_inline
    new.satuan := 'set';
  elsif new.set_id is not null then
    select ps.nama into v_set from public.product_sets ps where ps.id = new.set_id;
    new.deskripsi := coalesce(nullif(btrim(v_set), ''), '—');
    new.satuan := 'set';
  else
    select p.kode, p.usulan_teks, p.satuan into v_kode, v_teks, v_sat from public.products p where p.id = new.product_id;
    if lower(btrim(coalesce(new.deskripsi, ''))) is distinct from lower(btrim(coalesce(v_kode, '')))
       and lower(btrim(coalesce(new.deskripsi, ''))) is distinct from lower(btrim(coalesce(v_teks, v_kode, ''))) then
      new.deskripsi := coalesce(v_kode, '—');
    end if;
    if new.satuan is null or new.satuan not in ('pcs', coalesce(v_sat, 'pcs')) then
      new.satuan := coalesce(v_sat, 'pcs');
    end if;
  end if;
  return new;
end $function$;
