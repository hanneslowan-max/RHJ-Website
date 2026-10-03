-- ═══════════════════════════════════════════════════════════════════════
-- 118 · Perbaikan hasil audit keamanan (3 Oktober 2026)
--
--  (1) Tanggal SP diisi sistem. Tanggal SP menentukan price list pembanding
--      (isi_harga_list) dan periode laporan penjualan, jadi tidak boleh dipilih
--      bebas oleh pembuat SP. Saat SP dibuat, tanggal = hari ini WIB untuk semua
--      peran; sesudahnya hanya owner/GM (atau persetujuan GM, rhj.usul) yang boleh
--      mengubahnya — tercatat di audit log (zz_audit_sales_orders).
--      Sekaligus menutup selisih zona waktu: layar dulu mengirim tanggal UTC.
--  (2) Baris PO tidak bisa ditambah lagi bila PO sudah dipakai SP yang tidak batal,
--      kecuali owner/GM atau lewat persetujuan GM (putuskan_ubah, rhj.usul).
--      Menegakkan "Ubah PO lewat approval" dan invariant grand total SP = PO.
--  (3) Pengajuan ubah rekening PIC (pic_rekening_ubah):
--      - dibaca hanya oleh owner/GM, pengajunya, dan peran yang boleh melihat PIC
--        itu (RLS customer_pics) — dulu semua peran boleh_baca;
--      - diisi hanya lewat RPC ajukan_ubah_rekening (yang memeriksa pemegang
--        pelanggan) — policy INSERT langsung dicabut.
--  (4) Kunci rekening PIC (customer_pics.terkunci) tidak bisa dibuka tanpa
--      persetujuan GM (rhj.ubah_rekening), sama dengan penjagaan nomor rekeningnya.
--
-- Tidak ada data yang diubah. Pemeriksaan DEV sebelum migrasi: 54 SP semuanya
-- bertanggal sama dengan hari dibuatnya; 0 selisih SP vs PO; pic_rekening_ubah 0 baris.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) tanggal SP ───────────────────────────────────────────────────────
create or replace function public.jaga_tanggal_sp()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_hari_ini date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if auth.uid() is null then return new; end if;          -- migrasi / proses internal
  if tg_op = 'INSERT' then
    new.tanggal := v_hari_ini;
    return new;
  end if;
  if new.tanggal is distinct from old.tanggal
     and not public.boleh_ubah_langsung()
     and coalesce(current_setting('rhj.usul', true), '') <> 'on' then
    raise exception 'Tanggal Surat Pesanan % diisi sistem saat SP dibuat (menentukan price list pembanding). Hanya owner/GM yang boleh mengubahnya.', old.no_sp
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_tanggal_sp() from public, anon, authenticated;

drop trigger if exists so_b_tanggal on public.sales_orders;
create trigger so_b_tanggal before insert or update of tanggal on public.sales_orders
  for each row execute function public.jaga_tanggal_sp();

-- ── (2) baris PO sesudah dipakai SP ──────────────────────────────────────
create or replace function public.jaga_tambah_baris_po()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_no_po text;
begin
  if auth.uid() is null
     or public.boleh_ubah_langsung()
     or coalesce(current_setting('rhj.usul', true), '') = 'on' then
    return new;
  end if;
  if exists (select 1 from public.sales_orders s where s.po_id = new.po_id and not s.batal) then
    select no_po into v_no_po from public.purchase_orders where id = new.po_id;
    raise exception 'PO % sudah dipakai Surat Pesanan. Penambahan baris diajukan lewat "Minta ubah PO" — GM yang memutuskan.', coalesce(v_no_po, '')
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.jaga_tambah_baris_po() from public, anon, authenticated;

drop trigger if exists pol_a_jaga_tambah on public.po_lines;
create trigger pol_a_jaga_tambah before insert on public.po_lines
  for each row execute function public.jaga_tambah_baris_po();

-- ── (3) pengajuan ubah rekening PIC ──────────────────────────────────────
drop policy if exists pru_baca on public.pic_rekening_ubah;
create policy pru_baca on public.pic_rekening_ubah for select to authenticated
  using (
    public.boleh_approve()
    or diajukan_oleh = auth.uid()
    -- subquery ini tunduk pada RLS customer_pics (cpic_baca): sales hanya
    -- melihat PIC pelanggan miliknya / yang belum bertuan.
    or exists (select 1 from public.customer_pics p where p.id = pic_rekening_ubah.pic_id)
  );

drop policy if exists pru_tambah on public.pic_rekening_ubah;   -- isi hanya lewat ajukan_ubah_rekening()

-- ── (4) kunci rekening PIC ───────────────────────────────────────────────
create or replace function public.jaga_rekening_pic()
returns trigger language plpgsql security definer set search_path = public as $function$
begin
  if tg_op = 'INSERT' then
    new.terkunci := coalesce(btrim(new.no_rekening), '') <> '';
    new.dibuat_oleh := auth.uid();
    return new;
  end if;
  if old.terkunci
     and (new.bank is distinct from old.bank
       or new.no_rekening is distinct from old.no_rekening
       or new.atas_nama is distinct from old.atas_nama
       or new.terkunci is distinct from old.terkunci)          -- #118: kuncinya ikut dijaga
     -- coalesce penting: current_setting mengembalikan NULL kalau belum
     -- pernah diset, dan NULL <> 'on' itu NULL, bukan true — tanpa ini
     -- seluruh syaratnya jadi NULL dan penguncinya tidak pernah menggigit.
     and coalesce(current_setting('rhj.ubah_rekening', true), 'off') <> 'on' then
    raise exception 'Rekening % sudah terkunci. Ajukan perubahan lewat approval GM.', old.nama;
  end if;
  if not old.terkunci and coalesce(btrim(new.no_rekening), '') <> '' then
    new.terkunci := true;                 -- pengisian pertama langsung mengunci
  end if;
  return new;
end $function$;
