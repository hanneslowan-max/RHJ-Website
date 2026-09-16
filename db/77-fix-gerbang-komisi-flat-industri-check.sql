-- Berkas 77: dua perbaikan hasil audit rhj-verifikator (15 Sep 2026).
--
-- (#22) jaga_gerbang_komisi — celah: trigger gate klaim komisi memblok bila SP telat & gm_pct null,
--   TANPA mengecualikan rep komisi flat (Michael id7 / Riksa id8). komisi_hitung() & so_baris_hitung
--   sudah mendahulukan 1% flat atas telat; gate ini tertinggal. Perbaikan: ambil komisi_flat_pct rep;
--   bila flat, lewati syarat telat/gm_pct dan JANGAN isi pct_gm. Rep non-flat: perilaku IDENTIK.
--   Diverifikasi: definisi kini memuat cek 'komisi_flat_pct is not null'.
--
-- (#25) customers.industri — tambah CHECK (NULL atau 1 dari 3 nilai: Otomotif / Non Otomotif /
--   Bengkel Otomotif). Pertahanan lapis DB di atas dropdown FE (cegah teks bebas via REST).
--   Aman: semua 5395 baris industri kini NULL. industri_lama (cadangan) tak dibatasi.
--
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

create or replace function public.jaga_gerbang_komisi()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare s public.sales_orders; r public.so_ringkas; v_flat boolean;
begin
  select * into s from public.sales_orders where id = new.so_id;
  if not found then raise exception 'Surat Pesanan tidak ditemukan.'; end if;
  if s.batal then raise exception 'SP % sudah dibatalkan.', s.no_sp; end if;
  if not s.lunas then
    raise exception 'SP % belum ditandai terbayar. Komisi baru bisa diklaim '
                    'sesudah pelunasan dicatat.', s.no_sp;
  end if;
  select * into r from public.so_ringkas where so_id = new.so_id;
  if coalesce(r.ada_bawah_list, false) and s.harga_ok is not true then
    raise exception 'SP % masih punya baris di bawah price list yang belum diputus GM. '
                    'Komisinya belum bisa dihitung utuh.', s.no_sp;
  end if;
  select (rp.komisi_flat_pct is not null) into v_flat
    from public.sales_reps rp where rp.id = s.sales_rep_id;
  if s.telat and s.gm_pct is null and not coalesce(v_flat, false) then
    raise exception 'Invoice SP % dibayar lewat 120 hari dan GM belum menetapkan '
                    'persentase komisinya.', s.no_sp;
  end if;
  new.sales_rep_id := coalesce(new.sales_rep_id, s.sales_rep_id);
  new.telat        := coalesce(s.telat, false);
  new.pct_gm       := case when s.telat and not coalesce(v_flat, false) then s.gm_pct end;
  new.dibuat_oleh  := auth.uid();
  return new;
end $function$;

alter table public.customers drop constraint if exists customers_industri_cek;
alter table public.customers add constraint customers_industri_cek
  check (industri is null or industri in ('Otomotif','Non Otomotif','Bengkel Otomotif'));
