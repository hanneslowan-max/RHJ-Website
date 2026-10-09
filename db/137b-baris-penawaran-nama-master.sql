-- ═══════════════════════════════════════════════════════════════════════
-- 137b · Review adversarial berkas 137 (temuan "bypass", rendah–sedang): nama barang & satuan baris penawaran dari master
--
-- Celah (uji DEV, rollback): jaga_baris_quote (137) hanya memeriksa baris menunjuk produk/set/set inline; deskripsi dan
-- satuan tetap kiriman klien (simpan_penawaran: coalesce(b->>'deskripsi','—'), coalesce(b->>'satuan','pcs');
-- jaga_set_baris_quote hanya mengisi label set bila deskripsi kosong/'—'). Lewat POST /rpc/simpan_penawaran langsung,
-- peran yang boleh membuat penawaran bisa mencetak nama barang bebas ("Forklift Toyota 3 ton") pada baris set (judul
-- kolom Barang) atau baris produk (subjudul), dan satuan bebas — melompati aturan "barang di luar master hanya lewat
-- usulan item (#59)". Layar tidak pernah mengirim teks bebas: deskripsi produk = kode, set master = nama set, set inline
-- = label "Set <tipe> (<kombinasi>)" yang sama dengan label_set_inline; satuan produk "pcs", set "set".
-- Dampak: keutuhan dokumen saja (penawaran tidak mengalir ke PO/SP, komisi, HPP).
--
-- Perbaikan (jaga_baris_quote, BEFORE INSERT, menyala sebelum quote_lines_set_inline; peran bersesi saja):
--  · baris produk: deskripsi dipertahankan hanya bila sama dengan kode atau teks usulan barang itu (huruf besar-kecil &
--    spasi tepi tidak dihitung), selain itu = kode; satuan hanya 'pcs' atau satuan master barang itu, selain itu =
--    satuan master;
--  · baris set master: deskripsi = nama set, satuan = 'set';
--  · baris set inline: deskripsi dikosongkan ('—') → quote_lines_set_inline mengisi label dari isinya; satuan 'set'.
-- Spesifikasi tetap bebas (#40/#56, kolomnya sendiri di dokumen). Layar tidak berubah (yang dikirimnya sudah sama).
-- Data lama tidak diubah. Tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.jaga_baris_quote()
returns trigger language plpgsql security definer set search_path = public as $$
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
end $$;
comment on function public.jaga_baris_quote() is
  '137 (temuan #4): baris penawaran hanya lewat simpan_penawaran (transaksi & pembuat yang sama dengan kepala) dan wajib menunjuk produk/set/set inline. 137b: nama barang & satuan dari master.';
revoke all on function public.jaga_baris_quote() from public, anon, authenticated;

do $$ begin
  if position('137b' in pg_get_functiondef('public.jaga_baris_quote()'::regprocedure)) = 0 then
    raise exception '137b: jaga_baris_quote belum diperbarui';
  end if;
end $$;
