-- ═══════════════════════════════════════════════════════════════════════
-- 139u · Tindak lanjut review #55 (template penawaran): isi set master dibekukan di baris penawaran
-- (nomor 139u: jatah nomor sesi ini 120–139; "u" diurutkan sesudah 139t dan sebelum berkas EHC 140+.)
--
-- Temuan (review #55, no. 12): baris penawaran dengan set master hanya menyimpan set_id. Dokumen (detail & Unduh PDF)
-- mencetak "1 set = …" dari daftar set yang KEBETULAN termuat di layar, dengan isi set SEKARANG — penawaran yang sama
-- bisa tercetak berbeda tergantung riwayat sesi dan perubahan set master sesudahnya (simpan_set membuat ulang
-- komponennya). Set inline sudah dibekukan di set_komponen (berkas 108), set master belum (CHECK quote_lines_set_inline
-- melarang set_komponen bila set_id terisi).
--
-- Perubahan: kolom quote_lines.set_isi (jsonb, [{product_id, qty}]) diisi trigger BEFORE INSERT dari
-- product_set_components set itu saat baris disimpan — tidak pernah dari kiriman layar/REST (baris tanpa set_id → NULL).
-- Baris penawaran tidak bisa diubah sesudah disimpan (berkas 137), jadi isinya beku. Baris lama: NULL → dokumen tidak
-- mencetak "1 set = …" (spesifikasi "Isi: …" yang tersimpan tetap ada).
-- Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

alter table public.quote_lines add column if not exists set_isi jsonb;
comment on column public.quote_lines.set_isi is
  '139u: isi set master saat baris disimpan ([{product_id, qty}]) — diisi trigger, bukan kiriman layar.';

create or replace function public.quote_lines_isi_set()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.set_id is null then
    new.set_isi := null;
  else
    select jsonb_agg(jsonb_build_object('product_id', c.product_id, 'qty', c.qty) order by c.urut, c.id)
      into new.set_isi
      from public.product_set_components c
     where c.set_id = new.set_id;
  end if;
  return new;
end $$;
revoke all on function public.quote_lines_isi_set() from public, anon, authenticated;
create or replace trigger quote_lines_set_isi
  before insert on public.quote_lines
  for each row execute function public.quote_lines_isi_set();

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.quote_lines'::regclass and tgname = 'quote_lines_set_isi') then
    raise exception '139u: trigger quote_lines_set_isi belum terpasang';
  end if;
end $$;
