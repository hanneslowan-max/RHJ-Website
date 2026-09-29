-- ═══════════════════════════════════════════════════════════════════════
-- 115 · Perbaikan temuan verifikator revisi 29–49
--
-- Semua perbaikan menegakkan aturan yang SUDAH berlaku (ATURAN.md B) atau keputusan
-- Hannes; tidak ada aturan bisnis baru selain yang dicatat di ATURAN.md dalam commit ini.
--
--  (1) #32 hapus_produk: produk yang dipakai sebagai komponen SET INLINE (po_lines /
--      quote_lines.set_komponen) atau di usulan ubah yang masih menunggu kini terhitung
--      "sudah dipakai" → dinonaktifkan, tidak dihapus.
--  (2) #40 catat_spesifikasi_sales: teks yang SAMA dengan spesifikasi master tidak dicatat
--      sebagai "spesifikasi terakhir sales" (dan catatan lama dihapus) — revisi master
--      berikutnya tetap sampai ke sales itu.
--  (3) #29 PO baru wajib menunjuk pelanggan (customer_id) — dulu hanya dijaga layar; lewat
--      REST sales bisa membuat PO tanpa pelanggan atas nama pelanggan sales lain.
--      PO lama tanpa pelanggan tidak disentuh.
--  (4) #37 lengkapi_pelanggan_sp: pencocokan juga lewat No. HP (dulu buntu bila HP sudah
--      dipakai pelanggan lain); pelanggan yang dipegang sales LAIN ditolak (dulu SP sales A
--      ditautkan ke pelanggan sales B); hasil mengembalikan cara cocok & apakah kategori
--      pilihan Vonny dipakai.
--  (5) #36 policy storage lama bucket 'dokumen' (untuk dokumen impor) tidak lagi berlaku
--      untuk awalan penjualan po/, ehc/, komisi/ — dulu peran impor (selfie) bisa
--      mendaftar/mengunduh/menimpa lampiran PO & bukti klaim. Awalan itu kini hanya diatur
--      policy rhj_* masing-masing.
--  (6) #36 lampiran PO: berkas harus unggahan orang itu sendiri (owner/GM boleh berkas
--      siapa pun) dan belum menjadi lampiran PO lain — lewat lampirkan_po maupun insert.
--  (7) #29/#41 buat_pelanggan_baru: bentrok No. HP dengan pelanggan yang BUKAN milik sales
--      itu tidak lagi menyebut nama pelanggan & sales pemegangnya (pencarian balik HP).
--  (8) #30 mode PPN SP yang sudah ber-invoice tidak bisa diubah (dulu dijaga hanya dari PO;
--      SP tanpa PO bisa diubah sesudah invoice terbit).
--  (9) #30 laporan_penjualan potongan produk/kategori memakai DPP (sama dengan potongan
--      sales/pelanggan); harga_khusus_lengkap.dipakai_baris membandingkan DPP.
-- (10) #34 gm_konteks_keputusan (usulan ubah PO): harga efektif ikut penyesuaian pembulatan.
-- (11) #34 baris PO qty pecahan yang berdiskon/berpenyesuaian harus bisa dipecah persis ke
--      SP (nilai ÷ qty habis dalam sen) — dulu PO tersimpan tapi SP-nya tak pernah bisa dibuat.
--
-- Tidak ada data yang dihapus atau diubah nilainya.
-- ═══════════════════════════════════════════════════════════════════════

-- ── pembantu: No. HP baku (sama dengan buat_pelanggan_baru) ─────────────
create or replace function public.hp_baku(p_hp text)
returns text
language sql immutable parallel safe set search_path = '' as $$
  select case
    when x = '' then null
    when left(x, 1) = '0' then '62' || substr(x, 2)
    when left(x, 1) = '8' then '62' || x
    else x end
  from (select regexp_replace(coalesce(p_hp, ''), '\D', '', 'g') as x) t
$$;
grant execute on function public.hp_baku(text) to authenticated;

-- ── (1) #32 ──────────────────────────────────────────────────────────────
create or replace function public.hapus_produk(p_id bigint)
returns text
language plpgsql security definer set search_path = public as $$
declare v_kode text; v_pakai text;
begin
  if not public.boleh_hapus() then
    raise exception 'Hanya owner yang bisa menghapus produk.' using errcode = '42501';
  end if;
  select kode into v_kode from public.products where id = p_id;
  if v_kode is null then raise exception 'Produk #% tidak ditemukan.', p_id using errcode = 'P0002'; end if;
  select string_agg(x, ', ') into v_pakai from (
              select 'PO' as x          where exists (select 1 from public.po_lines               where product_id = p_id)
    union all select 'SP'               where exists (select 1 from public.sales_order_lines      where product_id = p_id)
    union all select 'penawaran'        where exists (select 1 from public.quote_lines            where product_id = p_id)
    union all select 'lead'             where exists (select 1 from public.leads                  where product_id = p_id)
    union all select 'set roda'         where exists (select 1 from public.product_set_components where product_id = p_id)
    union all select 'order impor'      where exists (select 1 from public.import_lines           where product_id = p_id)
    union all select 'harga khusus'     where exists (select 1 from public.harga_khusus           where product_id = p_id)
    -- berkas 115: komponen set inline / snapshot set (#28) dan usulan ubah yang masih menunggu
    union all select 'set di PO'        where exists (select 1 from public.po_lines l
                 cross join lateral jsonb_array_elements(case when jsonb_typeof(l.set_komponen) = 'array' then l.set_komponen else '[]'::jsonb end) e
                 where e->>'product_id' = p_id::text)
    union all select 'set di penawaran' where exists (select 1 from public.quote_lines l
                 cross join lateral jsonb_array_elements(case when jsonb_typeof(l.set_komponen) = 'array' then l.set_komponen else '[]'::jsonb end) e
                 where e->>'product_id' = p_id::text)
    union all select 'usulan ubah yang menunggu' where exists (select 1 from public.usul_ubah u
                 where u.status = 'menunggu'
                   and jsonb_path_exists(u.nilai_baru, '$.** ? (@.product_id == $n || @.product_id == $t)',
                                         jsonb_build_object('n', p_id, 't', p_id::text)))
  ) t;
  if v_pakai is not null then
    update public.products set aktif = false where id = p_id and aktif;
    return 'Produk ' || v_kode || ' sudah dipakai di ' || v_pakai
        || ' — tidak dihapus, tetapi dinonaktifkan: tidak muncul lagi di pilihan barang, riwayatnya tetap utuh.';
  end if;
  update public.factory_codes set product_id = null where product_id = p_id;   -- dilepas, tidak dihapus
  delete from public.products where id = p_id;                                -- price_list dkk. ikut (cascade)
  return 'Produk ' || v_kode || ' dihapus permanen (belum pernah dipakai transaksi).';
end $$;
revoke all on function public.hapus_produk(bigint) from public, anon;
grant execute on function public.hapus_produk(bigint) to authenticated;

-- ── (2) #40 ──────────────────────────────────────────────────────────────
create or replace function public.catat_spesifikasi_sales(p_quote bigint)
returns void
language plpgsql security definer set search_path = public as $function$
declare v_rep bigint;
begin
  if not public.boleh_tulis_quote(p_quote) then
    raise exception 'Anda tidak berhak mengubah penawaran ini.' using errcode = '42501';
  end if;
  select sales_rep_id into v_rep from public.quotes where id = p_quote;
  if v_rep is null then return; end if;
  -- Spesifikasi terakhir tiap produk di penawaran ini (baris terakhir menang). Hanya EDITAN sales —
  -- teks yang sama dengan master tidak dicatat, supaya revisi master tetap sampai ke sales ini.
  insert into public.spesifikasi_sales (product_id, sales_rep_id, spesifikasi, quote_id, diubah_pada, diubah_oleh)
  select a.product_id, v_rep, a.sp, p_quote, now(), auth.uid()
    from (select distinct on (l.product_id) l.product_id, btrim(coalesce(l.spesifikasi, '')) as sp
            from public.quote_lines l
           where l.quote_id = p_quote and l.product_id is not null
           order by l.product_id, l.urut desc) a
    join public.products p on p.id = a.product_id
   where a.sp <> '' and a.sp <> btrim(coalesce(p.spesifikasi, ''))
  on conflict (product_id, sales_rep_id) do update
     set spesifikasi = excluded.spesifikasi, quote_id = excluded.quote_id,
         diubah_pada = excluded.diubah_pada, diubah_oleh = excluded.diubah_oleh;
  -- Dikosongkan atau dikembalikan ke teks master → catatan sales untuk produk itu dilepas.
  delete from public.spesifikasi_sales s
   using (select distinct on (l.product_id) l.product_id, btrim(coalesce(l.spesifikasi, '')) as sp
            from public.quote_lines l
           where l.quote_id = p_quote and l.product_id is not null
           order by l.product_id, l.urut desc) a,
         public.products p
   where s.sales_rep_id = v_rep and s.product_id = a.product_id and p.id = a.product_id
     and (a.sp = '' or a.sp = btrim(coalesce(p.spesifikasi, '')));
end $function$;

-- ── (3) #29 PO baru wajib menunjuk pelanggan ─────────────────────────────
create or replace function public.jaga_pelanggan_po()
returns trigger
language plpgsql set search_path = public as $$
begin
  if new.customer_id is null and (tg_op = 'INSERT' or old.customer_id is not null) then
    raise exception 'PO wajib menunjuk pelanggan di data pelanggan. Pilih dari daftar, atau isi pelanggan baru '
                    '(nama, alamat, No. HP) — ia ikut tersimpan ke data pelanggan.' using errcode = '23502';
  end if;
  return new;
end $$;
revoke all on function public.jaga_pelanggan_po() from public, anon, authenticated;
drop trigger if exists po_b_wajib_pelanggan on public.purchase_orders;
create trigger po_b_wajib_pelanggan before insert or update of customer_id on public.purchase_orders
  for each row execute function public.jaga_pelanggan_po();

-- ── (4) #37 lengkapi_pelanggan_sp ────────────────────────────────────────
create or replace function public.lengkapi_pelanggan_sp(p_so bigint, p_industri text, p_hp text default null, p_alamat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s        public.sales_orders;
  v_ind    text := nullif(btrim(coalesce(p_industri, '')), '');
  v_cust   bigint;
  v_kunci  text;
  v_hp     text;
  v_cocok  text;
  v_dibuat boolean := false;
  v_pakai  boolean := true;
  v_ada    public.customers;
  v_sales  text;
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
    return jsonb_build_object('customer_id', s.customer_id, 'dibuat', false, 'dicocokkan', 'sudah', 'industri', v_ind,
                              'kategori_dipakai', true, 'nama', (select nama from public.customers where id = s.customer_id));
  end if;

  -- cocokkan: nama (tanpa PT/CV & tanda baca), lalu No. HP (berkas 115)
  v_kunci := public.kunci_nama_pelanggan(s.kepada);
  select c.* into v_ada from public.customers c
   where public.kunci_nama_pelanggan(c.nama) = v_kunci
      or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_kunci)
   order by c.id limit 1;
  if v_ada.id is not null then v_cocok := 'nama';
  else
    v_hp := public.hp_baku(coalesce(nullif(btrim(p_hp), ''), s.telp));
    if v_hp is not null then
      select c.* into v_ada from public.customers c where c.hp = v_hp order by c.id limit 1;
      if v_ada.id is not null then v_cocok := 'hp'; end if;
    end if;
  end if;

  if v_ada.id is not null then
    -- berkas 115: pelanggan bertuan hanya untuk sales pemegangnya (sama dengan RLS po/so _tambah)
    if v_ada.sales_rep_id is not null and s.sales_rep_id is not null and v_ada.sales_rep_id <> s.sales_rep_id then
      select nama into v_sales from public.sales_reps where id = v_ada.sales_rep_id;
      raise exception '% SP % cocok dengan pelanggan "%" yang dipegang sales %, bukan sales SP ini. '
                      'Pindahkan dulu pelanggannya ke sales SP (tab Pelanggan) atau ganti sales SP — owner/GM.',
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, coalesce(v_sales, '#' || v_ada.sales_rep_id)
        using errcode = '42501';
    end if;
    v_cust := v_ada.id;
    if v_ada.industri is null then update public.customers set industri = v_ind where id = v_cust;   -- yang sudah terisi tidak ditimpa
    else v_pakai := v_ada.industri = v_ind; end if;
  else
    v_cust := public.buat_pelanggan_baru(s.kepada, coalesce(nullif(btrim(p_hp), ''), s.telp),
                                         coalesce(nullif(btrim(p_alamat), ''), s.alamat), s.sales_rep_id);
    update public.customers set industri = v_ind where id = v_cust;
    v_dibuat := true; v_cocok := 'baru';
  end if;

  update public.sales_orders set customer_id = v_cust, diubah_pada = now(), diubah_oleh = auth.uid() where id = p_so;
  if s.po_id is not null then
    update public.purchase_orders set customer_id = v_cust where id = s.po_id and customer_id is null;
  end if;
  return jsonb_build_object('customer_id', v_cust, 'dibuat', v_dibuat, 'dicocokkan', v_cocok,
                            'kategori_dipakai', v_pakai,
                            'industri', (select industri from public.customers where id = v_cust),
                            'nama', (select nama from public.customers where id = v_cust));
end $$;
revoke all on function public.lengkapi_pelanggan_sp(bigint, text, text, text) from public, anon;
grant execute on function public.lengkapi_pelanggan_sp(bigint, text, text, text) to authenticated;

-- ── (5) #36 policy storage lama: bukan untuk awalan penjualan ───────────
drop policy if exists dokumen_baca on storage.objects;
create policy dokumen_baca on storage.objects for select
  using (bucket_id = 'dokumen' and public.boleh_lihat_impor()
         and name !~~ 'po/%' and name !~~ 'ehc/%' and name !~~ 'komisi/%');
drop policy if exists dokumen_tulis on storage.objects;
create policy dokumen_tulis on storage.objects for insert
  with check (bucket_id = 'dokumen' and public.boleh_alur_impor()
              and name !~~ 'po/%' and name !~~ 'ehc/%' and name !~~ 'komisi/%');
drop policy if exists dokumen_ubah on storage.objects;
create policy dokumen_ubah on storage.objects for update
  using (bucket_id = 'dokumen' and public.boleh_alur_impor()
         and name !~~ 'po/%' and name !~~ 'ehc/%' and name !~~ 'komisi/%')
  with check (bucket_id = 'dokumen' and public.boleh_alur_impor()
              and name !~~ 'po/%' and name !~~ 'ehc/%' and name !~~ 'komisi/%');

-- ── (6) #36 lampiran PO: milik sendiri & belum dipakai PO lain ───────────
create or replace function public.jaga_lampiran_po()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_ada boolean;
begin
  if new.lampiran is null or (tg_op = 'UPDATE' and new.lampiran is not distinct from old.lampiran) then
    return new;
  end if;
  if new.lampiran !~ '^po/' then raise exception 'Jalur lampiran PO tidak sah.' using errcode = '22023'; end if;
  select o.owner, true into v_owner, v_ada from storage.objects o
   where o.bucket_id = 'dokumen' and o.name = new.lampiran;
  if v_ada is null then raise exception 'Berkas lampiran belum terunggah.' using errcode = 'P0002'; end if;
  if v_owner is distinct from auth.uid() and not public.setara_owner() then
    raise exception 'Berkas lampiran itu bukan unggahan Anda.' using errcode = '42501';
  end if;
  if exists (select 1 from public.purchase_orders p where p.lampiran = new.lampiran and p.id is distinct from new.id) then
    raise exception 'Berkas itu sudah menjadi lampiran PO lain.' using errcode = '23505';
  end if;
  return new;
end $$;
revoke all on function public.jaga_lampiran_po() from public, anon, authenticated;
drop trigger if exists po_c_lampiran on public.purchase_orders;
create trigger po_c_lampiran before insert or update of lampiran on public.purchase_orders
  for each row execute function public.jaga_lampiran_po();

-- ── (7) buat_pelanggan_baru: bentrok HP tanpa membuka pelanggan sales lain ──
do $$
declare v text; w text;
begin
  v := pg_get_functiondef('public.buat_pelanggan_baru(text, text, text, bigint)'::regprocedure);
  w := replace(v, $a$  select c.nama, sr.nama as sales into v_ada
    from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
   where c.hp = v_hp limit 1;
  if found then$a$, $a$  select c.nama, sr.nama as sales, c.sales_rep_id into v_ada
    from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
   where c.hp = v_hp limit 1;
  -- berkas 115: untuk sales, pelanggan sales lain tidak disebut (bukan jalan pencarian balik HP → pelanggan)
  if found and v_peran = 'sales' and v_ada.sales_rep_id is not null and v_ada.sales_rep_id is distinct from v_rep then
    raise exception 'Nomor HP itu sudah terdaftar pada pelanggan lain yang bukan pelanggan Anda. '
                    'Kalau perusahaannya sama, hubungi owner/GM.';
  end if;
  if found then$a$);
  if w = v then raise exception 'buat_pelanggan_baru: blok cek HP tidak ditemukan.'; end if;
  execute w;
end $$;

-- ── (8) #30 mode PPN SP ber-invoice terkunci ─────────────────────────────
create or replace function public.sinkron_mode_ppn()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_po text;
begin
  if tg_op = 'INSERT' then
    new.mode_ppn := coalesce(new.mode_ppn, case when coalesce(new.ppn_kena, true) then 'exclude' else 'non' end);
  elsif new.mode_ppn is distinct from old.mode_ppn then
    new.mode_ppn := coalesce(new.mode_ppn, old.mode_ppn);          -- mode yang ditulis menang
  elsif new.ppn_kena is distinct from old.ppn_kena then            -- klien lama: hanya ppn_kena
    new.mode_ppn := case when new.ppn_kena then 'exclude' else 'non' end;
  end if;
  -- #30: SP yang menunjuk PO selalu memakai mode PPN PO-nya (dinilai saat SP dibuat, saat PO-nya
  -- ditempel/diganti, atau saat mode/ppn_kena SP disentuh — bukan pada setiap update lain).
  -- IF bersarang: PL/pgSQL tidak memotong AND, jadi new.po_id / no_invoice tidak boleh disebut untuk purchase_orders.
  if tg_table_name = 'sales_orders' then
    if new.po_id is not null
       and (tg_op = 'INSERT' or new.po_id is distinct from old.po_id
            or new.mode_ppn is distinct from old.mode_ppn or new.ppn_kena is distinct from old.ppn_kena) then
      select p.mode_ppn into v_po from public.purchase_orders p where p.id = new.po_id;
      if v_po is not null then new.mode_ppn := v_po; end if;
    end if;
    -- berkas 115: invoice/faktur mengikuti mode PPN → SP yang sudah ber-invoice tidak berganti mode
    if tg_op = 'UPDATE' and old.no_invoice is not null and new.mode_ppn is distinct from old.mode_ppn then
      raise exception 'Mode PPN Surat Pesanan % tidak bisa diubah: sudah ber-invoice (%). Perbaiki invoicenya dulu.',
        old.no_sp, old.no_invoice using errcode = '23514';
    end if;
  end if;
  new.ppn_kena := new.mode_ppn <> 'non';
  return new;
end $$;
revoke all on function public.sinkron_mode_ppn() from public, anon, authenticated;

-- ── (9) #30 laporan & harga khusus dari DPP ──────────────────────────────
do $$
declare v text; w text;
begin
  v := pg_get_functiondef('public.laporan_penjualan(date, date, text)'::regprocedure);
  if (length(v) - length(replace(v, 'coalesce(sum(b.nilai_barang), 0)', ''))) / length('coalesce(sum(b.nilai_barang), 0)') <> 2
     or (length(v) - length(replace(v, 'coalesce(sum(b.nilai_ehc), 0)', ''))) / length('coalesce(sum(b.nilai_ehc), 0)') <> 2 then
    raise exception 'laporan_penjualan: bentuk cabang produk/kategori tidak seperti yang diharapkan.';
  end if;
  w := replace(v, 'coalesce(sum(b.nilai_barang), 0)', 'coalesce(sum(b.nilai_barang_dpp), 0)');   -- #30 (berkas 115)
  w := replace(w, 'coalesce(sum(b.nilai_ehc), 0)', 'coalesce(sum(b.nilai_ehc_dpp), 0)');
  execute w;

  v := pg_get_viewdef('public.harga_khusus_lengkap'::regclass, true);
  w := replace(v, 'l.harga_nett >= h.harga_nett', 'dpp_ppn(l.harga_nett, o.mode_ppn, l.jenis) >= h.harga_nett');
  if w = v then raise exception 'harga_khusus_lengkap: pembanding harga tidak ditemukan.'; end if;
  execute 'create or replace view public.harga_khusus_lengkap as ' || w;   -- view ini memang tanpa security_invoker (sebelumnya pun begitu)

-- ── (10) #34 konteks HPP GM: penyesuaian pembulatan ikut harga efektif ──
  v := pg_get_functiondef('public.gm_konteks_keputusan(text, bigint)'::regprocedure);
  w := replace(v, $a$                      else public.dpp_ppn(coalesce(nullif(x->>'diskon','')::numeric, 0), v.mppn, 'barang') end as u_disk,$a$,
                  $a$                      else public.dpp_ppn(coalesce(nullif(x->>'diskon','')::numeric, 0), v.mppn, 'barang') end as u_disk,
                 public.dpp_ppn(coalesce(nullif(x->>'penyesuaian','')::numeric, 0), v.mppn, 'barang') as u_pj,   -- #34 (berkas 115)$a$);
  if w = v then raise exception 'gm_konteks_keputusan: kolom diskon tidak ditemukan.'; end if;
  v := w;
  w := replace(v, $a$                           when b.u_dtipe = 'persen' then b.u_harga * (1 - b.u_disk / 100)
                           else b.u_harga - b.u_disk / b.u_qty end as u_eff$a$,
                  $a$                           when b.u_dtipe = 'persen' then b.u_harga * (1 - b.u_disk / 100) + b.u_pj / b.u_qty
                           else b.u_harga - b.u_disk / b.u_qty + b.u_pj / b.u_qty end as u_eff$a$);
  if w = v then raise exception 'gm_konteks_keputusan: rumus harga efektif tidak ditemukan.'; end if;
  execute w;
end $$;

-- ── (11) #34 qty pecahan berdiskon/berpenyesuaian harus bisa dipecah ke SP ──
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'po_lines_pecahan_terbagi') then
    alter table public.po_lines add constraint po_lines_pecahan_terbagi check (
      qty = trunc(qty) or set_id is not null or set_komponen is not null
      or (coalesce(diskon, 0) = 0 and penyesuaian = 0)
      or ((qty * harga
           - case when coalesce(diskon_tipe, 'rp') = 'persen' then qty * harga * coalesce(diskon, 0) / 100 else coalesce(diskon, 0) end
           + penyesuaian) / qty)
         = trunc((qty * harga
           - case when coalesce(diskon_tipe, 'rp') = 'persen' then qty * harga * coalesce(diskon, 0) / 100 else coalesce(diskon, 0) end
           + penyesuaian) / qty, 2));
  end if;
end $$;

do $$
declare v text; w text;
begin
  v := pg_get_functiondef('public.periksa_baris_po_usul(jsonb)'::regprocedure);
  w := replace(v, $a$    if coalesce(nullif(x->>'jenis', ''), 'barang') = 'barang'$a$,
                  $a$    -- berkas 115: qty pecahan berdiskon/berpenyesuaian → nilai ÷ qty harus habis dalam sen (bisa jadi harga nett SP)
    if q <> trunc(q) and not coalesce(v_set, false) and (d > 0 or pj <> 0) then   -- v_set bisa NULL
      if (bruto - case when t = 'persen' then bruto * d / 100 else d end + pj) / q
         <> trunc((bruto - case when t = 'persen' then bruto * d / 100 else d end + pj) / q, 2) then
        raise exception 'Baris %: qty % pecahan — nilai sesudah diskon/pembulatan tidak bisa dibagi rata ke qty itu. '
                        'Pakai qty bilangan bulat atau ubah totalnya.', i, trim_scale(q);
      end if;
    end if;
    if coalesce(nullif(x->>'jenis', ''), 'barang') = 'barang'$a$);
  if w = v then raise exception 'periksa_baris_po_usul: titik sisip tidak ditemukan.'; end if;
  execute w;
end $$;
