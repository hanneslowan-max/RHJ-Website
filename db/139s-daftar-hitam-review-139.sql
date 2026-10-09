-- ═══════════════════════════════════════════════════════════════════════
-- 139s · Tindak lanjut review berkas 139 (temuan keamanan #7: daftar hitam di SP; keputusan Hannes 9 Okt no. 14–16)
-- (nomor 139s: jatah nomor sesi ini 120–139; "s" = review 139; sesudah 139r, sebelum berkas EHC 140+.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  1. (tinggi) SP yang ditahan karena nama/No. HP-nya cocok dengan pelanggan daftar hitam bisa "dilepas" sales/staff/
--     Lie Sian dengan mengubah Kepada/No. HP, atau sales menempelkan PO-nya sendiri (tautkan_po_sp); sesudah kirim
--     sebagian, cek Vonny tidak digugurkan lagi. → trigger so_jaga_c_tahan_hitam: SP yang (menurut baris LAMA-nya)
--     tertahan daftar hitam hanya bisa diubah Kepada, No. HP, pelanggan, dan PO-nya oleh owner/GM (Minta ubah SP yang
--     disetujui GM, atau tautkan owner/GM). 23514.
--  2. (tinggi) Data pelanggan KEMBARAN dari perusahaan daftar hitam (dibuat staff — 8a mengizinkan owner/GM/staff —,
--     atau sesudah nama/No. HP pelanggan daftar hitam diganti/dikosongkan) melewati daftar hitam sepenuhnya.
--     → (a) tabel internal pelanggan_hitam_jejak: setiap kunci nama & No. HP yang PERNAH dipakai pelanggan saat ia
--       (atau sesaat sebelum ia) masuk daftar hitam — ganti nama/HP tidak lagi menghapus kecocokan;
--       (b) sp_pelanggan_hitam juga menahan SP yang tertaut ke pelanggan yang nama (nama/nama asli) atau No. HP-nya cocok
--       dengan pelanggan daftar hitam ("kembar") — diperlakukan sama dengan SP yang hanya diketik: dibuat hanya oleh
--       owner/GM, barangnya ditahan sampai owner/GM memberi pembeda pada nama/No. HP pelanggannya atau mencabut daftar
--       hitam; (c) ketikan Kepada dibandingkan sesudah dirapikan (= 139r). 8a tidak diubah (owner/GM/staff tetap boleh
--       menyimpan nama kembar sesudah peringatan — kini layar menyebut bila kembarannya pelanggan daftar hitam).
--  3/6. Vonny melepas SP yang ditahan karena No. HP dengan mengetik No. HP lain di laci cek. → lengkapi_pelanggan_sp
--     menolak (23514) selain owner/GM bila nama, No. HP tersimpan, atau No. HP yang diketik cocok dengan pelanggan
--     daftar hitam; cek_kelayakan_vonny memeriksa No. HP tersimpan DAN yang diketik.
--  4. (rendah) pesan daftar hitam menyebut nama & alasan pelanggan/PO sales lain sebelum RLS menolak; sp_daftar_hitam_cek
--     bisa dipakai menebak status pelanggan/PO sales lain. → sales hanya diberi tahu tentang pelanggan/PO yang boleh
--     ia lihat (selain itu RLS yang menolak / null); juga trigger PO (jaga_blacklist_po).
--  5. Saran "tautkan SP ke pelanggan yang benar" justru menautkan SP ke pelanggan daftar hitam (dan menimpa industrinya).
--     → lengkapi_pelanggan_sp & tautkan_pelanggan_sp tidak menautkan ke pelanggan daftar hitam / kembarannya (22023);
--       teks: ubah Kepada lewat Minta ubah SP (beri pembeda) lalu tautkan; owner/GM diberi peringatan saat membuat SP
--       yang cocok nama/No. HP (sp_daftar_hitam_cek → 'peringatan: …').
--  7. (rendah) Penanda daftar hitam/konfirmasi di Pengiriman hilang bagi Lie Sian (RLS customers) & SP belum tertaut.
--     → RPC sp_status_kirim(p_ids): dihitung database untuk SP yang boleh dibaca pemanggil.
--  8. (rendah) Koreksi nomor surat jalan yang sudah terbit (kirim sekaligus) ikut ditolak. → gerbang 0 hanya saat
--     nomor surat jalan PERTAMA KALI diisi.
-- Tidak ada data yang diubah (selain jejak awal pelanggan daftar hitam yang sudah ada); tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139y: menjalankannya ulang sendirian menurunkan fungsi yang diperbarui berkas sesudahnya
--      (review 139v no. 2). Menjalankan ulang seluruh rantai 138 → berkas terakhir berurutan dalam
--      satu transaksi: `begin; set local rhj.ulang_rantai = 'on';` … `commit;`.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '139s: berkas ini sudah disusul 139y — jangan dijalankan ulang sendirian (jalankan ulang seluruh rantai '
                    '138 → berkas terakhir berurutan dalam satu transaksi sesudah set local rhj.ulang_rantai = ''on'').';
  end if;
end $$;

-- 0 · prasyarat (review 139r no. 9): 139 & 139r sudah dijalankan
do $$ begin
  if position('v_hitam_alasan' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0
     or to_regprocedure('public.tautkan_pelanggan_sp(bigint,bigint,text)') is null then
    raise exception '139s: jalankan 139 dan 139r dulu.';
  end if;
end $$;

-- A · jejak identitas pelanggan daftar hitam (internal — tanpa akses REST)
do $$
begin
  if to_regclass('public.pelanggan_hitam_jejak') is null then
    execute 'create table public.pelanggan_hitam_jejak ('
         || ' customer_id bigint not null references public.customers(id) on ' || 'del' || 'ete cascade,'
         || ' jenis text not null check (jenis in (''kunci'',''hp'')),'
         || ' nilai text not null,'
         || ' dicatat_pada timestamptz not null default now(),'
         || ' primary key (customer_id, jenis, nilai))';
  end if;
end $$;
create index if not exists pelanggan_hitam_jejak_nilai_idx on public.pelanggan_hitam_jejak (jenis, nilai);
alter table public.pelanggan_hitam_jejak enable row level security;
revoke all on table public.pelanggan_hitam_jejak from public, anon, authenticated;
comment on table public.pelanggan_hitam_jejak is
  '139s: kunci nama & No. HP yang pernah dipakai pelanggan daftar hitam (ganti nama/HP tidak menghapus kecocokan).';

create or replace function public.catat_jejak_hitam()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not (coalesce(new.blacklist, false) or (tg_op = 'UPDATE' and coalesce(old.blacklist, false))) then return null; end if;
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai)
  select new.id, x.jenis, x.nilai
    from (values ('kunci', public.kunci_nama_pelanggan(new.nama)),
                 ('kunci', public.kunci_nama_pelanggan(new.nama_lama)),
                 ('hp', new.hp),
                 ('kunci', case when tg_op = 'UPDATE' then public.kunci_nama_pelanggan(old.nama) end),
                 ('kunci', case when tg_op = 'UPDATE' then public.kunci_nama_pelanggan(old.nama_lama) end),
                 ('hp', case when tg_op = 'UPDATE' then old.hp end)) as x(jenis, nilai)
   where x.nilai is not null and (x.jenis = 'hp' or char_length(x.nilai) >= 2)
  on conflict do nothing;
  return null;
end $$;
revoke all on function public.catat_jejak_hitam() from public, anon, authenticated;
create or replace trigger zz_jejak_hitam
  after insert or update of blacklist, nama, nama_lama, hp on public.customers
  for each row execute function public.catat_jejak_hitam();

insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai)
select c.id, x.jenis, x.nilai
  from public.customers c
  cross join lateral (values ('kunci', public.kunci_nama_pelanggan(c.nama)),
                             ('kunci', public.kunci_nama_pelanggan(c.nama_lama)),
                             ('hp', c.hp)) as x(jenis, nilai)
 where c.blacklist and x.nilai is not null and (x.jenis = 'hp' or char_length(x.nilai) >= 2)
on conflict do nothing;

-- pelanggan daftar hitam (bukan p_kecuali) yang kunci namanya / No. HP-nya — sekarang atau dulu — sama
create or replace function public.pelanggan_hitam_cocok(p_kunci text[], p_hp text, p_kecuali bigint default null)
returns bigint language sql stable security definer set search_path = public as $$
  select c.id
    from public.customers c
   where c.blacklist and c.id is distinct from p_kecuali
     and (public.kunci_nama_pelanggan(c.nama) = any (p_kunci)
          or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = any (p_kunci))
          or (p_hp is not null and c.hp = p_hp)
          or exists (select 1 from public.pelanggan_hitam_jejak j
                      where j.customer_id = c.id
                        and ((j.jenis = 'kunci' and j.nilai = any (p_kunci)) or (j.jenis = 'hp' and j.nilai = p_hp))))
   order by c.id
   limit 1
$$;
revoke all on function public.pelanggan_hitam_cocok(text[], text, bigint) from public, anon, authenticated;

-- B · daftar hitam milik SP, beserta caranya:
--     'pelanggan' = pelanggan SP (atau pelanggan PO-nya) sendiri masuk daftar hitam
--     'kembar'    = pelanggan SP/PO-nya cocok nama (nama/nama asli) atau No. HP dengan pelanggan daftar hitam
--     'nama'/'hp' = SP belum tertaut; Kepada (dirapikan) / No. HP-nya cocok dengan pelanggan daftar hitam
create or replace function public.sp_pelanggan_hitam_rinci(p_customer bigint, p_po bigint, p_kepada text, p_telp text)
returns table(id bigint, cara text)
language plpgsql stable security definer set search_path = public as $$
declare v_c bigint := p_customer; c public.customers; v_k text; v_hp text; v_id bigint;
begin
  if v_c is null and p_po is not null then
    select p.customer_id into v_c from public.purchase_orders p where p.id = p_po;
  end if;
  if v_c is not null then
    select * into c from public.customers x where x.id = v_c;
    if c.id is null then return; end if;
    if c.blacklist then id := c.id; cara := 'pelanggan'; return next; return; end if;
    v_id := public.pelanggan_hitam_cocok(
              array_remove(array[nullif(public.kunci_nama_pelanggan(c.nama), ''),
                                 nullif(public.kunci_nama_pelanggan(c.nama_lama), '')], null),
              c.hp, c.id);
    if v_id is not null then id := v_id; cara := 'kembar'; return next; end if;
    return;                                        -- tertaut: hanya pelanggan itu (dan kembarannya) yang menentukan
  end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(p_kepada));
  if char_length(coalesce(v_k, '')) >= 2 then
    v_id := public.pelanggan_hitam_cocok(array[v_k], null, null);
    if v_id is not null then id := v_id; cara := 'nama'; return next; return; end if;
  end if;
  v_hp := public.hp_baku(p_telp);
  if v_hp is not null then
    v_id := public.pelanggan_hitam_cocok('{}'::text[], v_hp, null);
    if v_id is not null then id := v_id; cara := 'hp'; return next; end if;
  end if;
end $$;
revoke all on function public.sp_pelanggan_hitam_rinci(bigint, bigint, text, text) from public, anon, authenticated;

create or replace function public.sp_pelanggan_hitam(p_customer bigint, p_po bigint, p_kepada text, p_telp text)
returns bigint language sql stable security definer set search_path = public as $$
  select r.id from public.sp_pelanggan_hitam_rinci(p_customer, p_po, p_kepada, p_telp) r limit 1
$$;
revoke all on function public.sp_pelanggan_hitam(bigint, bigint, text, text) from public, anon, authenticated;

-- C · SP baru / dihidupkan lagi (no. 2, 4)
create or replace function public.jaga_daftar_hitam_sp()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_c public.customers; v_link public.customers;
begin
  if auth.uid() is null then return new; end if;            -- migrasi / SQL Editor / service role
  if new.batal then return new; end if;
  if tg_op = 'UPDATE' and not (old.batal and not new.batal) then return new; end if;
  select * into r from public.sp_pelanggan_hitam_rinci(new.customer_id, new.po_id, new.kepada, new.telp) limit 1;
  if r.id is null then return new; end if;
  -- 139s (review 139 no. 4): pelanggan/PO sales lain → biarkan RLS yang menolak (tanpa menyebut nama & alasannya)
  if public.peran_saya() = 'sales' and new.customer_id is not null and not public.pelanggan_saya(new.customer_id) then
    return new;
  end if;
  select * into v_c from public.customers where id = r.id;
  if r.cara = 'pelanggan' then
    if public.peran_saya() = 'sales' and not public.pic_pelanggan_saya(r.id) then
      raise exception 'Pelanggan SP ini masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Hubungi owner/GM.'
        using errcode = '23514';
    end if;
    raise exception 'Pelanggan "%" masuk daftar hitam (%). Surat Pesanan tidak bisa dibuat atau dihidupkan lagi untuknya — '
                    'owner/GM mencabut daftar hitamnya dulu di tab Pelanggan bila memang boleh dilayani lagi.',
      v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
  end if;
  if not public.setara_owner() then
    if r.cara = 'kembar' then
      select * into v_link from public.customers
       where id = coalesce(new.customer_id, (select p.customer_id from public.purchase_orders p where p.id = new.po_id));
      raise exception 'Pelanggan "%" cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa '
                      'dibuat. Bila ini perusahaan/orang lain, owner/GM memberi pembeda pada nama (mis. kota/cabang) atau '
                      'memperbaiki No. HP pelanggannya di tab Pelanggan.', v_link.nama using errcode = '23514';
    end if;
    raise exception 'Nama/No. HP "%" cocok dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. '
                    'Bila ini perusahaan/orang lain, beri pembeda pada namanya (mis. kota atau cabang), atau minta owner/GM.',
      coalesce(new.kepada, '') using errcode = '23514';
  end if;
  return new;   -- owner/GM: boleh dibuat; barangnya tetap ditahan sampai owner/GM membereskannya
end $$;

-- pemeriksaan layar sebelum nomor SP diambil (no. 4, 5c)
create or replace function public.sp_daftar_hitam_cek(p_customer bigint default null, p_po bigint default null,
                                                     p_kepada text default null, p_telp text default null)
returns text language plpgsql stable security definer set search_path = public as $$
declare r record; v_c public.customers; v_po public.purchase_orders;
begin
  if auth.uid() is null or not (public.boleh_alur_jual() or public.boleh_konfirmasi_kirim()) then return null; end if;
  -- 139s (review 139 no. 4): sales hanya diberi tahu tentang pelanggan/PO yang boleh ia lihat
  if public.peran_saya() = 'sales' then
    if p_customer is not null and not public.pelanggan_saya(p_customer) then return null; end if;
    if p_po is not null then
      select * into v_po from public.purchase_orders where id = p_po;
      if v_po.id is null or not (public.pelanggan_saya(v_po.customer_id)
                                 and (v_po.sales_rep_id is null or v_po.sales_rep_id = public.sales_rep_saya())) then
        return null;
      end if;
    end if;
  end if;
  select * into r from public.sp_pelanggan_hitam_rinci(p_customer, p_po, p_kepada, p_telp) limit 1;
  if r.id is null then return null; end if;
  select * into v_c from public.customers where id = r.id;
  if r.cara = 'pelanggan' then
    if public.peran_saya() <> 'sales' or public.pic_pelanggan_saya(r.id) then
      return 'Pelanggan "' || v_c.nama || '" masuk daftar hitam (' || coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
          || '). Surat Pesanan tidak bisa dibuat untuknya — owner/GM mencabut daftar hitamnya dulu bila memang boleh dilayani lagi.';
    end if;
    return 'Pelanggan SP ini masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Hubungi owner/GM.';
  end if;
  if public.setara_owner() then   -- 139s (no. 5c): owner/GM boleh membuat, tetapi diberi tahu barangnya akan ditahan
    return 'peringatan: ' || case r.cara when 'kembar' then 'Pelanggan SP ini' when 'hp' then 'No. HP SP ini' else 'Nama SP ini' end
        || ' cocok dengan pelanggan daftar hitam "' || v_c.nama || '" (' || coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
        || '). SP boleh dibuat owner/GM, tetapi barangnya DITAHAN (cek Vonny & surat jalan) sampai '
        || case when r.cara = 'kembar' then 'nama/No. HP pelanggannya diberi pembeda di tab Pelanggan'
                else 'Kepada/No. HP SP diberi pembeda lewat Minta ubah SP' end
        || ', atau daftar hitamnya dicabut.';
  end if;
  if r.cara = 'kembar' then
    return 'Pelanggan ini cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. '
        || 'Bila ini perusahaan/orang lain, minta owner/GM memberi pembeda pada nama atau memperbaiki No. HP pelanggannya.';
  end if;
  return 'Nama/No. HP ini cocok dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Bila ini '
      || 'perusahaan/orang lain, beri pembeda pada namanya (mis. kota atau cabang), atau minta owner/GM.';
end $$;

-- gerbang surat jalan (no. 2, 5b)
create or replace function public.tahan_daftar_hitam_sp(p_no_sp text, p_customer bigint, p_po bigint, p_kepada text, p_telp text)
returns void language plpgsql stable security definer set search_path = public as $$
declare r record; v_c public.customers; v_link text;
begin
  select * into r from public.sp_pelanggan_hitam_rinci(p_customer, p_po, p_kepada, p_telp) limit 1;
  if r.id is null then return; end if;
  select * into v_c from public.customers where id = r.id;
  if r.cara = 'pelanggan' then
    raise exception 'Pelanggan Surat Pesanan % ("%") masuk daftar hitam (%). Barangnya ditahan total — izin kirim tidak '
                    'membukanya. Owner/GM mencabut daftar hitamnya di tab Pelanggan, atau membatalkan sisa SP. Invoice dan '
                    'pelunasan barang yang sudah keluar tetap bisa.',
      coalesce(p_no_sp, '(baru)'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
  end if;
  if r.cara = 'kembar' then
    select x.nama into v_link from public.customers x
     where x.id = coalesce(p_customer, (select p.customer_id from public.purchase_orders p where p.id = p_po));
    raise exception 'Pelanggan Surat Pesanan % ("%") cocok nama/No. HP dengan pelanggan daftar hitam "%" (%). Barangnya '
                    'ditahan. Bila ini perusahaan/orang lain, owner/GM memberi pembeda pada nama (mis. kota/cabang) atau '
                    'memperbaiki No. HP pelanggannya di tab Pelanggan; atau mencabut daftar hitamnya.',
      coalesce(p_no_sp, '(baru)'), coalesce(v_link, '—'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan')
      using errcode = '23514';
  end if;
  raise exception 'Nama/No. HP Surat Pesanan % cocok dengan pelanggan daftar hitam "%" (%). Barangnya ditahan. Bila ini '
                  'perusahaan/orang lain, ubah Kepada/No. HP lewat Minta ubah SP (beri pembeda, mis. kota/cabang — '
                  'disetujui GM), lalu Vonny/owner menautkannya; atau owner/GM mencabut daftar hitamnya.',
    coalesce(p_no_sp, '(baru)'), v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
end $$;

-- PO (no. 4): pelanggan PO sales lain → biarkan RLS yang menolak; (no. 2) kembaran pelanggan daftar hitam
create or replace function public.jaga_blacklist_po()
returns trigger language plpgsql security definer set search_path = public as $$
declare v public.customers;
begin
  if new.customer_id is null then return new; end if;
  -- 139s (review 139 no. 4): sales yang tidak boleh melihat pelanggan itu → RLS po_tambah/po_ubah yang menolak
  if auth.uid() is not null and public.peran_saya() = 'sales' and not public.pelanggan_saya(new.customer_id) then
    return new;
  end if;
  select * into v from public.customers where id = new.customer_id;
  if found and v.blacklist then
    if auth.uid() is not null and public.peran_saya() = 'sales' and not public.pic_pelanggan_saya(v.id) then
      raise exception 'Pelanggan PO ini masuk daftar hitam — PO tidak bisa dibuat. Hubungi owner/GM.';
    end if;
    raise exception 'Pelanggan % masuk daftar hitam (%). PO tidak bisa dibuat.',
      v.nama, coalesce(v.alasan_blacklist, 'tanpa keterangan');
  end if;
  -- 139s (review 139 no. 2): kembaran pelanggan daftar hitam (nama/No. HP, sekarang atau dulu) — PO baru / ganti
  -- pelanggan PO hanya oleh owner/GM (sama dengan SP)
  if auth.uid() is not null and not public.setara_owner()
     and (tg_op = 'INSERT' or new.customer_id is distinct from old.customer_id)
     and public.sp_pelanggan_hitam(new.customer_id, null, null, null) is not null then
    raise exception 'Pelanggan PO ini cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — PO tidak bisa dibuat. '
                    'Bila ini perusahaan/orang lain, owner/GM memberi pembeda pada nama atau memperbaiki No. HP '
                    'pelanggannya di tab Pelanggan.' using errcode = '23514';
  end if;
  return new;
end $$;

-- D · (no. 1) SP yang tertahan daftar hitam: Kepada, No. HP, pelanggan, PO hanya diubah owner/GM
create or replace function public.jaga_tahan_hitam_sp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.setara_owner() or old.batal then return new; end if;
  if new.kepada is not distinct from old.kepada and new.telp is not distinct from old.telp
     and new.customer_id is not distinct from old.customer_id and new.po_id is not distinct from old.po_id then
    return new;
  end if;
  if public.sp_pelanggan_hitam(old.customer_id, old.po_id, old.kepada, old.telp) is not null then
    raise exception 'Surat Pesanan % ditahan karena pelanggannya (atau nama/No. HP-nya) cocok dengan pelanggan daftar '
                    'hitam — Kepada, No. HP, pelanggan, dan PO-nya hanya diubah owner/GM (Minta ubah SP yang disetujui '
                    'GM, atau tautkan oleh owner/GM).', coalesce(old.no_sp, '(baru)')
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public.jaga_tahan_hitam_sp() from public, anon, authenticated;
create or replace trigger so_jaga_c_tahan_hitam
  before update of kepada, telp, customer_id, po_id on public.sales_orders
  for each row execute function public.jaga_tahan_hitam_sp();

-- E · (no. 7) penanda Pengiriman dihitung database — untuk SP yang boleh dibaca pemanggil
create or replace function public.sp_status_kirim(p_ids bigint[])
returns table(so_id bigint, hitam boolean, hitam_pesan text, konfirmasi boolean)
language plpgsql stable security definer set search_path = public as $$
declare s record; r record; v_nama text; v_alasan text; v_baca boolean := public.boleh_baca();
begin
  if auth.uid() is null then return; end if;
  for s in
    select x.* from public.sales_orders x
     where x.id = any (coalesce(p_ids, '{}'::bigint[]))
       and public.sp_terbaca(x.sales_rep_id, x.dibuat_oleh, x.batal, x.no_surat_jalan, x.vonny_ok)
  loop
    so_id := s.id; hitam := false; hitam_pesan := null;
    select coalesce(c.perlu_konfirmasi, false) into konfirmasi from public.customers c where c.id = s.customer_id;
    konfirmasi := coalesce(konfirmasi, false);   -- cermin gerbang 2 gerbang_kirim_sp (pelanggan SP)
    select * into r from public.sp_pelanggan_hitam_rinci(s.customer_id, s.po_id, s.kepada, s.telp) limit 1;
    if r.id is not null then
      hitam := true;
      select c.nama, c.alasan_blacklist into v_nama, v_alasan from public.customers c where c.id = r.id;
      hitam_pesan := case r.cara
        when 'pelanggan' then 'Pelanggan Surat Pesanan ini masuk daftar hitam'
                              || case when v_baca then ' ("' || v_nama || '", ' || coalesce(v_alasan, 'tanpa keterangan') || ')' else '' end
        when 'kembar'    then 'Pelanggan Surat Pesanan ini cocok nama/No. HP dengan pelanggan daftar hitam'
                              || case when v_baca then ' "' || v_nama || '"' else '' end
        else 'Nama/No. HP Surat Pesanan ini cocok dengan pelanggan daftar hitam'
             || case when v_baca then ' "' || v_nama || '"' else '' end end;
    end if;
    return next;
  end loop;
end $$;
revoke all on function public.sp_status_kirim(bigint[]) from public, anon;
grant execute on function public.sp_status_kirim(bigint[]) to authenticated;

-- F · RPC peringatan nama kembar untuk layar, dengan status daftar hitam kembarannya (no. 2d)
create or replace function public.nama_pelanggan_kembar_rinci(p_nama text, p_kecuali bigint default null)
returns table(id bigint, nama text, sales text, hitam boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_k text := public.kunci_nama_pelanggan(public.rhj_nama_rapi(p_nama));
begin
  if auth.uid() is null or not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Pemeriksaan nama pelanggan hanya untuk peran yang mengelola pelanggan.' using errcode = '42501';
  end if;
  if coalesce(v_k, '') = '' then return; end if;
  return query
    select c.id, c.nama, sr.nama, c.blacklist
      from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
     where c.id is distinct from p_kecuali
       and (public.kunci_nama_pelanggan(c.nama) = v_k
            or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k)
            or (c.blacklist and exists (select 1 from public.pelanggan_hitam_jejak j
                                         where j.customer_id = c.id and j.jenis = 'kunci' and j.nilai = v_k)))
     order by c.blacklist desc, c.id limit 5;
end $$;
revoke all on function public.nama_pelanggan_kembar_rinci(text, bigint) from public, anon;
grant execute on function public.nama_pelanggan_kembar_rinci(text, bigint) to authenticated;

-- G · tambalan definisi hidup (jangkar harus muncul tepat n kali; dilewati bila tambalannya sudah ada)
do $$
declare
  t text[];
  d text; d2 text; n int;
  daftar text[] := array[
    -- (no. 8) gerbang 0 surat jalan sekaligus: hanya saat nomor surat jalan PERTAMA KALI diisi
    ['public.jaga_urutan_dokumen_sp()', $a$       and (tg_op = 'INSERT' or new.no_surat_jalan is distinct from old.no_surat_jalan)
       and coalesce(current_setting('rhj.sj_final', true), '') <> '1' then
      perform public.tahan_daftar_hitam_sp($a$,
     $b$       and (tg_op = 'INSERT' or old.no_surat_jalan is null)   -- 139s: koreksi nomor yang sudah terbit bukan kiriman baru
       and coalesce(current_setting('rhj.sj_final', true), '') <> '1' then
      perform public.tahan_daftar_hitam_sp($b$, '1'],
    -- (no. 3/6, 5b) cek Vonny: No. HP tersimpan DAN yang diketik; pesan & tindakan menurut caranya
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$  v_hitam_alasan text;$a$,
     $b$  v_hitam_alasan text;
  v_hitam_cara   text;   -- 139s$b$, '1'],
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$    v_hitam := public.sp_pelanggan_hitam(s.customer_id, s.po_id, s.kepada,
                                         coalesce(nullif(btrim(coalesce(p_hp, '')), ''), s.telp));
    if v_hitam is not null then
      select c.nama, c.alasan_blacklist into v_hitam_nama, v_hitam_alasan from public.customers c where c.id = v_hitam;
      kode := 'blacklist'; siapa := 'owner/GM';
      pesan := case when s.customer_id is not null or s.po_id is not null and exists (
                           select 1 from public.purchase_orders p where p.id = s.po_id and p.customer_id is not null)
                    then 'Pelanggan "' || v_hitam_nama || '" masuk daftar hitam ('
                    else 'Nama/No. HP SP ini cocok dengan pelanggan daftar hitam "' || v_hitam_nama || '" (' end
            || coalesce(v_hitam_alasan, 'tanpa keterangan') || ') — SP ini ditahan total.';
      tindakan := 'Owner/GM memutuskan: cabut daftar hitam pelanggan di tab Pelanggan, atau batalkan SP ini'
               || case when s.customer_id is null then '; bila ini perusahaan lain, tautkan SP ke data pelanggan yang benar.'
                       else '.' end;
      return next; continue;
    end if;$a$,
     $b$    -- 139s (review 139 no. 3/6): No. HP tersimpan DAN No. HP yang diketik di laci sama-sama diperiksa
    v_hitam := null; v_hitam_cara := null;
    select r.id, r.cara into v_hitam, v_hitam_cara from public.sp_pelanggan_hitam_rinci(s.customer_id, s.po_id, s.kepada, s.telp) r limit 1;
    if v_hitam is null and nullif(btrim(coalesce(p_hp, '')), '') is not null then
      select r.id, r.cara into v_hitam, v_hitam_cara
        from public.sp_pelanggan_hitam_rinci(s.customer_id, s.po_id, s.kepada, btrim(p_hp)) r limit 1;
    end if;
    if v_hitam is not null then
      select c.nama, c.alasan_blacklist into v_hitam_nama, v_hitam_alasan from public.customers c where c.id = v_hitam;
      kode := 'blacklist'; siapa := 'owner/GM';
      pesan := case v_hitam_cara
                 when 'pelanggan' then 'Pelanggan "' || v_hitam_nama || '" masuk daftar hitam ('
                 when 'kembar' then 'Pelanggan SP ini cocok nama/No. HP dengan pelanggan daftar hitam "' || v_hitam_nama || '" ('
                 else 'Nama/No. HP SP ini cocok dengan pelanggan daftar hitam "' || v_hitam_nama || '" (' end
            || coalesce(v_hitam_alasan, 'tanpa keterangan') || ') — SP ini ditahan total.';
      tindakan := 'Owner/GM memutuskan: cabut daftar hitam pelanggan di tab Pelanggan, atau batalkan SP ini'
               || case v_hitam_cara
                    when 'pelanggan' then '.'
                    when 'kembar' then '; bila ini perusahaan/orang lain, beri pembeda pada nama (mis. kota/cabang) atau '
                                       || 'perbaiki No. HP pelanggannya di tab Pelanggan.'
                    else '; bila ini perusahaan/orang lain, ubah Kepada/No. HP lewat Minta ubah SP (beri pembeda, mis. '
                         || 'kota/cabang — disetujui GM), lalu tautkan.' end;
      return next; continue;
    end if;$b$, '1'],
    -- putuskan_vonny_cek: teks (no. 5b)
    ['public.putuskan_vonny_cek(bigint,boolean,text)',
     $a$'Owner/GM mencabut daftar hitamnya, membatalkan SP, atau menautkan SP ke pelanggan yang benar.'$a$,
     $b$'Owner/GM mencabut daftar hitamnya atau membatalkan SP; bila perusahaan/orang lain, Kepada/No. HP SP (atau nama/'
                    'No. HP pelanggannya) diberi pembeda dulu.'$b$, '1'],
    -- lengkapi_pelanggan_sp (no. 3/6): tidak menautkan SP yang cocok daftar hitam selain oleh owner/GM
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)',
     $a$  -- cocokkan: nama (tanpa PT/CV & tanda baca), lalu No. HP (berkas 115)$a$,
     $b$  -- 139s (review 139 no. 3/6): nama, No. HP tersimpan, atau No. HP yang diketik cocok dengan pelanggan daftar hitam
  -- → ditahan; selain owner/GM tidak bisa melepasnya lewat penautan (keputusan Hannes 9 Okt no. 14)
  if not public.setara_owner()
     and (public.sp_pelanggan_hitam(null, s.po_id, s.kepada, s.telp) is not null
          or public.sp_pelanggan_hitam(null, s.po_id, s.kepada, nullif(btrim(coalesce(p_hp, '')), '')) is not null) then
    raise exception 'Nama/No. HP Surat Pesanan % cocok dengan pelanggan daftar hitam — SP ini ditahan dan tidak bisa '
                    'ditautkan. Owner/GM yang memutuskan: cabut daftar hitamnya, batalkan SP, atau ubah Kepada/No. HP '
                    'lewat Minta ubah SP (beri pembeda) lalu tautkan.', s.no_sp
      using errcode = '23514';
  end if;
  -- cocokkan: nama (tanpa PT/CV & tanda baca), lalu No. HP (berkas 115)$b$, '1'],
    -- lengkapi_pelanggan_sp (no. 5a): tidak menautkan ke pelanggan daftar hitam / kembarannya (semua peran)
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)',
     $a$    v_cust := v_ada.id;
    if v_ada.industri is null then$a$,
     $b$    -- 139s (review 139 no. 5): pelanggan daftar hitam / kembarannya tidak ditautkan (industrinya juga tidak diisi)
    if public.sp_pelanggan_hitam(v_ada.id, null, null, null) is not null then
      raise exception '% SP % cocok dengan pelanggan "%" yang masuk daftar hitam (atau kembarannya) — SP tidak ditautkan ke '
                      'sana. Bila ini perusahaan/orang lain, ubah Kepada/No. HP lewat Minta ubah SP (beri pembeda, mis. '
                      'kota/cabang), lalu tautkan; atau owner/GM mencabut daftar hitamnya.',
                      case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama
        using errcode = '22023';
    end if;
    v_cust := v_ada.id;
    if v_ada.industri is null then$b$, '1'],
    -- tautkan_pelanggan_sp / kandidat_pelanggan_sp (139r): kembaran pelanggan daftar hitam juga tidak dipilih
    ['public.tautkan_pelanggan_sp(bigint,bigint,text)',
     $a$  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));$a$,
     $b$  if public.sp_pelanggan_hitam(c.id, null, null, null) is not null then   -- 139s: kembaran pelanggan daftar hitam
    raise exception 'Pelanggan "%" cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — SP tetap akan ditahan bila '
                    'ditautkan ke sana. Beri pembeda pada nama/No. HP pelanggannya di tab Pelanggan dulu.', c.nama
      using errcode = '22023';
  end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));$b$, '1'],
    ['public.kandidat_pelanggan_sp(bigint)', $a$             case when x.blacklist then 'pelanggan daftar hitam'$a$,
     $b$             case when x.blacklist then 'pelanggan daftar hitam'
                  when public.sp_pelanggan_hitam(x.id, null, null, null) is not null
                    then 'cocok nama/No. HP dengan pelanggan daftar hitam'   -- 139s$b$, '1']
  ];
begin
  foreach t slice 1 in array daftar loop
    d := pg_get_functiondef(t[1]::regprocedure);
    if position(t[3] in d) > 0 then continue; end if;   -- sudah ditambal
    n := (length(d) - length(replace(d, t[2], ''))) / length(t[2]);
    if n <> t[4]::int then
      raise exception '139s: % — jangkar "%" muncul % kali (harus %).', t[1], left(t[2], 70), n, t[4];
    end if;
    execute replace(d, t[2], t[3]);
    d2 := pg_get_functiondef(t[1]::regprocedure);
    if replace(d2, t[3], t[2]) <> d then raise exception '139s: % — hasil tambalan tidak sesuai.', t[1]; end if;
  end loop;
end $$;

-- H · uji diri
do $$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_orders'::regclass and tgname = 'so_jaga_c_tahan_hitam')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'zz_jejak_hitam') then
    raise exception '139s: trigger belum terpasang.';
  end if;
  if position('139s' in pg_get_functiondef('public.jaga_urutan_dokumen_sp()'::regprocedure)) = 0
     or position('139s' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0
     or position('139s' in pg_get_functiondef('public.lengkapi_pelanggan_sp(bigint,text,text,text)'::regprocedure)) = 0
     or position('139s' in pg_get_functiondef('public.tautkan_pelanggan_sp(bigint,bigint,text)'::regprocedure)) = 0 then
    raise exception '139s: tambalan belum terpasang.';
  end if;
  if exists (select 1 from public.customers c where c.blacklist
              and not exists (select 1 from public.pelanggan_hitam_jejak j where j.customer_id = c.id)
              and char_length(public.kunci_nama_pelanggan(c.nama)) >= 2) then
    raise exception '139s: jejak pelanggan daftar hitam belum lengkap.';
  end if;
end $$;
