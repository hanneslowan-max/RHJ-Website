-- ═══════════════════════════════════════════════════════════════════════
-- 112 · Lampiran PO (#36) & pelanggan SP yang belum ada di master (#37)
--
--  #36  Berkas PO customer disimpan di bucket 'dokumen' dengan awalan 'po/…',
--       jalurnya di purchase_orders.lampiran (kolom lama, dulu tak pernah
--       diisi layar). Policy storage:
--         · unggah  — peran yang boleh input PO (boleh_input_po)
--         · baca    — hanya bila PO yang menunjuk berkas itu TERLIHAT oleh
--                     pembaca (subkueri purchase_orders tunduk RLS po_baca):
--                     sales pemilik PO, dan peran lihat-semua-jual (termasuk Vonny)
--         · hapus   — pengunggah, selama berkasnya belum dipakai PO mana pun
--                     (membersihkan unggahan yang PO-nya gagal disimpan)
--       RPC lampirkan_po(p_po, p_path): menempelkan berkas ke PO yang sudah ada
--       (mis. lupa melampirkan). Hanya bila lampirannya masih kosong; owner/GM
--       boleh mengganti.
--  #37  lengkapi_pelanggan_sp(p_so, p_industri, p_hp, p_alamat) — dipakai cek
--       Vonny. SP yang pelanggannya belum ada di master (customer_id NULL,
--       mis. perorangan) dulu tidak bisa diberi kategori sama sekali. Sekarang:
--       nama SP dicocokkan ke master (tanpa PT/CV & tanda baca); ketemu → ditautkan,
--       tidak ketemu → pelanggan dibuat (buat_pelanggan_baru: wajib HP & alamat,
--       sales PIC = sales SP). Kategori diisi, SP (dan PO-nya bila pelanggannya
--       kosong) ditautkan ke pelanggan itu.
--
-- Tidak ada data yang dihapus.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) #36 policy storage untuk po/ ─────────────────────────────────────
drop policy if exists rhj_po_lampiran_tulis on storage.objects;
create policy rhj_po_lampiran_tulis on storage.objects for insert to authenticated
  with check (bucket_id = 'dokumen' and name like 'po/%' and public.boleh_input_po());

drop policy if exists rhj_po_lampiran_baca on storage.objects;
create policy rhj_po_lampiran_baca on storage.objects for select to authenticated
  using (bucket_id = 'dokumen' and name like 'po/%'
         and exists (select 1 from public.purchase_orders p where p.lampiran = objects.name));

drop policy if exists rhj_po_lampiran_hapus on storage.objects;
create policy rhj_po_lampiran_hapus on storage.objects for delete to authenticated
  using (bucket_id = 'dokumen' and name like 'po/%' and owner = auth.uid()
         and not exists (select 1 from public.purchase_orders p where p.lampiran = objects.name));

-- ── (2) #36 tempel lampiran ke PO yang sudah ada ────────────────────────
create or replace function public.lampirkan_po(p_po bigint, p_path text)
returns text
language plpgsql security definer set search_path = public as $$
declare v record; v_path text := btrim(coalesce(p_path, ''));
begin
  if not public.boleh_input_po() then
    raise exception 'Anda tidak berwenang melampirkan berkas PO.' using errcode = '42501';
  end if;
  select * into v from public.purchase_orders where id = p_po;
  if v.id is null
     or not (public.boleh_lihat_semua_jual()
             or (public.peran_saya() = 'sales' and v.sales_rep_id = public.sales_rep_saya())) then
    raise exception 'PO #% tidak ditemukan.', p_po using errcode = 'P0002';
  end if;
  if v_path !~ '^po/' then raise exception 'Jalur lampiran PO tidak sah.' using errcode = '22023'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'dokumen' and o.name = v_path) then
    raise exception 'Berkas lampiran belum terunggah.' using errcode = 'P0002';
  end if;
  if v.lampiran is not null and not public.setara_owner() then
    raise exception 'PO % sudah punya lampiran. Menggantinya wewenang owner/GM.', v.no_po using errcode = '42501';
  end if;
  update public.purchase_orders set lampiran = v_path, diubah_pada = now(), diubah_oleh = auth.uid() where id = p_po;
  return 'Lampiran PO ' || v.no_po || ' tersimpan.';
end $$;
revoke all on function public.lampirkan_po(bigint, text) from public, anon;
grant execute on function public.lampirkan_po(bigint, text) to authenticated;

-- ── (3) #37 pelanggan SP yang belum ada di master ───────────────────────
create or replace function public.lengkapi_pelanggan_sp(p_so bigint, p_industri text, p_hp text default null, p_alamat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s        public.sales_orders;
  v_ind    text := nullif(btrim(coalesce(p_industri, '')), '');
  v_cust   bigint;
  v_kunci  text;
  v_dibuat boolean := false;
  v_ada    public.customers;
begin
  if not public.boleh_konfirmasi_kirim() then
    raise exception 'Hanya owner, GM, atau Vonny yang boleh melengkapi pelanggan SP.' using errcode = '42501';
  end if;
  if v_ind is null or v_ind not in ('Otomotif','Non Otomotif','Bengkel Otomotif') then
    raise exception 'Kategori industri hanya Otomotif, Non Otomotif, atau Bengkel Otomotif.' using errcode = '22023';
  end if;
  select * into s from public.sales_orders where id = p_so for update;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode = '22023'; end if;

  if s.customer_id is not null then
    perform public.set_industri_pelanggan(s.customer_id, v_ind);
    return jsonb_build_object('customer_id', s.customer_id, 'dibuat', false, 'industri', v_ind);
  end if;

  v_kunci := public.kunci_nama_pelanggan(s.kepada);
  select c.* into v_ada from public.customers c
   where public.kunci_nama_pelanggan(c.nama) = v_kunci
      or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci)
   order by c.id limit 1;
  if v_ada.id is not null then
    v_cust := v_ada.id;
    if v_ada.industri is null then update public.customers set industri = v_ind where id = v_cust; end if;   -- yang sudah terisi tidak ditimpa
  else
    v_cust := public.buat_pelanggan_baru(s.kepada, coalesce(nullif(btrim(p_hp), ''), s.telp),
                                         coalesce(nullif(btrim(p_alamat), ''), s.alamat), s.sales_rep_id);
    update public.customers set industri = v_ind where id = v_cust;
    v_dibuat := true;
  end if;

  update public.sales_orders set customer_id = v_cust, diubah_pada = now(), diubah_oleh = auth.uid() where id = p_so;
  if s.po_id is not null then
    update public.purchase_orders set customer_id = v_cust where id = s.po_id and customer_id is null;
  end if;
  return jsonb_build_object('customer_id', v_cust, 'dibuat', v_dibuat,
                            'industri', (select industri from public.customers where id = v_cust),
                            'nama', (select nama from public.customers where id = v_cust));
end $$;
revoke all on function public.lengkapi_pelanggan_sp(bigint, text, text, text) from public, anon;
grant execute on function public.lengkapi_pelanggan_sp(bigint, text, text, text) to authenticated;
