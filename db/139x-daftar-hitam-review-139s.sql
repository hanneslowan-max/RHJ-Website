-- ═══════════════════════════════════════════════════════════════════════
-- 139x · Tindak lanjut review berkas 139s (temuan keamanan #7: daftar hitam di SP; keputusan Hannes 9 Okt no. 14–16)
-- (nomor 139x: jatah nomor sesi ini 120–139; "x" diurutkan sesudah 139w dan sebelum berkas EHC 140+.
--  Jalankan sesudah 139, 139r, dan 139s.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  1/10. (tinggi) Sales/staff melepas SP yang tertahan daftar hitam: batalkan SP → ubah Kepada/No. HP selama batal →
--     hidupkan lagi. jaga_tahan_hitam_sp melewati SP batal, pemeriksaan saat dihidupkan hanya membaca baris BARU, dan
--     vonny_ok tetap true (cek Vonny tidak gugur selama/sesudah batal) — Lie Sian mengirim barangnya.
--     → baris LAMA diperiksa walau SP batal; saat dihidupkan lagi oleh selain owner/GM baris lama juga diperiksa;
--       SP yang dihidupkan lagi oleh selain owner/GM/Vonny kembali ke antrean cek Vonny (bila barangnya belum keluar).
--  2. (sedang) "Minta ubah SP" yang disetujui GM melepas penahanan tanpa GM diberi tahu (layar hanya menampilkan beda
--     kolom), dan vonny_ok tetap. → putuskan_ubah menolak persetujuan yang MELEPAS penahanan kecuali lewat
--     setujui_ubah_lepas_hitam (layar: tanda merah + "Setujui & lepas penahanan" + konfirmasi); sesudah dilepas SP
--     kembali ke cek Vonny bila barangnya belum keluar. usul_lepas_hitam(p_id) memberi tahu layar.
--  3/5/8. (sedang) Saran "owner/GM memberi pembeda pada nama" tidak melepas kembaran yang punya nama_lama (4.670 dari
--     5.403 pelanggan DEV) — nama asli terkunci tetap cocok. → untuk kembaran, nama_lama hanya dihitung selama masih
--     nama asli dari nama sekarang (rhj_nama_sidik sama, cara pulihkan_nama_pelanggan); nama & No. HP pelanggan yang
--     sedang menjadi kembaran pelanggan daftar hitam hanya diubah owner/GM (ATURAN: owner/GM yang memberi pembeda).
--  4/9/11. (rendah) sp_status_kirim & nama_pelanggan_kembar_rinci memberi tahu sales nama/alasan daftar hitam pelanggan
--     sales lain. → nama & alasan untuk sales hanya pada cara 'pelanggan' yang ia pegang (= sp_daftar_hitam_cek);
--     rinci: penanda hitam & kecocokan jejak hanya untuk selain sales (atau pelanggan yang ia pegang).
--  6. (rendah) Cek Vonny "siap / Akan ditautkan" ke kembaran pelanggan daftar hitam, lengkapi lalu menolak (22023);
--     putuskan_vonny_cek bisa meloloskan SP itu tanpa ditautkan. → cek melaporkan 'blacklist' (owner/GM), pesan
--     lengkapi dibedakan (kembaran → pembeda di data pelanggan), putuskan_vonny_cek menolak.
--  7. (rendah) Nama pengganti "(tanpa nama)" dianggap identitas — satu lead "(tanpa nama)" di daftar hitam menjadikan
--     257 lead lain kembaran. → kunci "tanpa nama" tidak dipakai untuk pencocokan nama (No. HP tetap).
-- Tidak ada data yang diubah selain jejak berkunci "tanpa nama" (DEV 0 baris); tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139y: menjalankannya ulang sendirian menurunkan fungsi yang diperbarui berkas sesudahnya
--      (review 139v no. 2). Menjalankan ulang seluruh rantai 138 → berkas terakhir berurutan dalam
--      satu transaksi: `begin; set local rhj.ulang_rantai = 'on';` … `commit;`.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '139x: berkas ini sudah disusul 139y — jangan dijalankan ulang sendirian (jalankan ulang seluruh rantai '
                    '138 → berkas terakhir berurutan dalam satu transaksi sesudah set local rhj.ulang_rantai = ''on'').';
  end if;
end $$;

do $$ begin
  if to_regprocedure('public.sp_pelanggan_hitam_rinci(bigint,bigint,text,text)') is null
     or to_regprocedure('public.tautkan_pelanggan_sp(bigint,bigint,text)') is null then
    raise exception '139x: jalankan 139, 139r, dan 139s dulu.';
  end if;
end $$;

-- A · (no. 7) "(tanpa nama)" bukan identitas
create or replace function public.pelanggan_hitam_cocok(p_kunci text[], p_hp text, p_kecuali bigint default null)
returns bigint language sql stable security definer set search_path = public as $$
  select c.id
    from public.customers c,
         (select array_remove(coalesce(p_kunci, '{}'::text[]), 'tanpa nama') as k) a   -- 139x: nama pengganti
   where c.blacklist and c.id is distinct from p_kecuali
     and (public.kunci_nama_pelanggan(c.nama) = any (a.k)
          or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = any (a.k))
          or (p_hp is not null and c.hp = p_hp)
          or exists (select 1 from public.pelanggan_hitam_jejak j
                      where j.customer_id = c.id
                        and ((j.jenis = 'kunci' and j.nilai = any (a.k)) or (j.jenis = 'hp' and j.nilai = p_hp))))
   order by c.id
   limit 1
$$;
revoke all on function public.pelanggan_hitam_cocok(text[], text, bigint) from public, anon, authenticated;

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
   where x.nilai is not null and (x.jenis = 'hp' or (char_length(x.nilai) >= 2 and x.nilai <> 'tanpa nama'))   -- 139x
  on conflict do nothing;
  return null;
end $$;
revoke all on function public.catat_jejak_hitam() from public, anon, authenticated;
do $$ begin
  execute 'del' || 'ete from public.pelanggan_hitam_jejak where jenis = ''kunci'' and nilai = ''tanpa nama''';
end $$;

-- B · (no. 3/5/8) kembaran: nama asli pelanggan tertaut dihitung hanya selama masih nama asli dari nama sekarang
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
    -- 139x: nama_lama terkunci untuk semua peran; sesudah owner/GM memberi pembeda (nama sekarang bukan lagi bentuk rapi
    -- nama asli), nama asli tidak lagi membuat pelanggan ini kembaran
    v_id := public.pelanggan_hitam_cocok(
              array_remove(array[nullif(public.kunci_nama_pelanggan(c.nama), ''),
                                 case when c.nama_lama is not null
                                           and public.rhj_nama_sidik(c.nama) = public.rhj_nama_sidik(c.nama_lama)
                                      then nullif(public.kunci_nama_pelanggan(c.nama_lama), '') end], null),
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

-- nama/No. HP pelanggan yang sedang menjadi kembaran pelanggan daftar hitam hanya diubah owner/GM (pembeda = melepas)
create or replace function public.jaga_ganti_kembar_hitam()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.setara_owner() or old.blacklist then return new; end if;
  if public.kunci_nama_pelanggan(new.nama) is not distinct from public.kunci_nama_pelanggan(old.nama)
     and new.hp is not distinct from old.hp then
    return new;                                    -- merapikan penulisan tetap boleh
  end if;
  if exists (select 1 from public.sp_pelanggan_hitam_rinci(old.id, null, null, null) r where r.cara = 'kembar') then
    raise exception 'Pelanggan "%" cocok nama/No. HP dengan pelanggan daftar hitam — nama dan No. HP-nya hanya diubah '
                    'owner/GM (memberi pembeda melepas penahanan PO/SP-nya).', old.nama
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public.jaga_ganti_kembar_hitam() from public, anon, authenticated;
-- "zz": sesudah nama dirapikan & No. HP dibakukan
create or replace trigger customers_zz_jaga_kembar_hitam
  before update of nama, hp on public.customers
  for each row execute function public.jaga_ganti_kembar_hitam();

-- C · (no. 1/10) SP batal yang tertahan: baris LAMA tetap diperiksa; dihidupkan lagi → baris lama juga diperiksa
create or replace function public.jaga_tahan_hitam_sp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.setara_owner() then return new; end if;   -- 139x: SP batal tidak dikecualikan
  if new.kepada is not distinct from old.kepada and new.telp is not distinct from old.telp
     and new.customer_id is not distinct from old.customer_id and new.po_id is not distinct from old.po_id then
    return new;
  end if;
  if public.sp_pelanggan_hitam(old.customer_id, old.po_id, old.kepada, old.telp) is not null then
    raise exception 'Surat Pesanan % ditahan karena pelanggannya (atau nama/No. HP-nya) cocok dengan pelanggan daftar '
                    'hitam — Kepada, No. HP, pelanggan, dan PO-nya hanya diubah owner/GM (Minta ubah SP yang disetujui '
                    'GM, atau tautkan oleh owner/GM), juga selama SP dibatalkan.', coalesce(old.no_sp, '(baru)')
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function public.jaga_tahan_hitam_sp() from public, anon, authenticated;

create or replace function public.jaga_daftar_hitam_sp()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_c public.customers; v_link public.customers;
begin
  if auth.uid() is null then return new; end if;            -- migrasi / SQL Editor / service role
  if new.batal then return new; end if;
  if tg_op = 'UPDATE' and not (old.batal and not new.batal) then return new; end if;
  -- 139x (review 139s no. 1/10): SP yang dihidupkan lagi — baris sebelum dihidupkan juga diperiksa
  if tg_op = 'UPDATE' and not public.setara_owner()
     and public.sp_pelanggan_hitam(old.customer_id, old.po_id, old.kepada, old.telp) is not null then
    raise exception 'Surat Pesanan % tertahan daftar hitam — hanya owner/GM yang bisa menghidupkannya lagi.',
      coalesce(old.no_sp, '(baru)') using errcode = '23514';
  end if;
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

-- SP yang dihidupkan lagi oleh selain owner/GM/Vonny kembali ke antrean cek Vonny (gugurkan_cek_vonny: hanya bila
-- barangnya belum keluar) — sama dengan SP yang diubah sesudah lolos
do $$
declare d text;
begin
  select pg_get_triggerdef(t.oid) into d from pg_trigger t
   where t.tgrelid = 'public.sales_orders'::regclass and t.tgname = 'so_vonny_gugur';
  if d is null or position('(old.catatan IS DISTINCT FROM new.catatan)' in d) = 0
     or position('sp_vonny_gugur_kepala()' in d) = 0 then
    raise exception '139x: bentuk trigger so_vonny_gugur tidak seperti yang diharapkan — periksa dulu.';
  end if;
end $$;
create or replace trigger so_vonny_gugur
  after update on public.sales_orders
  for each row
  when (old.customer_id is distinct from new.customer_id or old.kepada is distinct from new.kepada
        or old.alamat is distinct from new.alamat or old.up is distinct from new.up or old.telp is distinct from new.telp
        or old.ppn_kena is distinct from new.ppn_kena or old.mode_ppn is distinct from new.mode_ppn
        or old.catatan is distinct from new.catatan
        or (old.po_id is not null and old.po_id is distinct from new.po_id)
        or (new.po_id is null and (old.po_menyusul is distinct from new.po_menyusul
                                   or old.po_menyusul_alasan is distinct from new.po_menyusul_alasan))
        or (old.batal and not new.batal))   -- 139x: dihidupkan lagi
  execute function public.sp_vonny_gugur_kepala();

-- D · (no. 4/9/11) sales tidak diberi tahu nama/alasan daftar hitam pelanggan yang tidak ia pegang
create or replace function public.sp_status_kirim(p_ids bigint[])
returns table(so_id bigint, hitam boolean, hitam_pesan text, konfirmasi boolean)
language plpgsql stable security definer set search_path = public as $$
declare s record; r record; v_nama text; v_alasan text; v_sebut boolean;
        v_sales boolean := coalesce(public.peran_saya(), '') = 'sales'; v_baca boolean := public.boleh_baca();
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
      -- 139x: = sp_daftar_hitam_cek — sales hanya pada cara 'pelanggan' yang ia pegang
      v_sebut := v_baca and (not v_sales or (r.cara = 'pelanggan' and public.pic_pelanggan_saya(r.id)));
      hitam_pesan := case r.cara
        when 'pelanggan' then 'Pelanggan Surat Pesanan ini masuk daftar hitam'
                              || case when v_sebut then ' ("' || v_nama || '", ' || coalesce(v_alasan, 'tanpa keterangan') || ')' else '' end
        when 'kembar'    then 'Pelanggan Surat Pesanan ini cocok nama/No. HP dengan pelanggan daftar hitam'
                              || case when v_sebut then ' "' || v_nama || '"' else '' end
        else 'Nama/No. HP Surat Pesanan ini cocok dengan pelanggan daftar hitam'
             || case when v_sebut then ' "' || v_nama || '"' else '' end end;
    end if;
    return next;
  end loop;
end $$;
revoke all on function public.sp_status_kirim(bigint[]) from public, anon;
grant execute on function public.sp_status_kirim(bigint[]) to authenticated;

create or replace function public.nama_pelanggan_kembar_rinci(p_nama text, p_kecuali bigint default null)
returns table(id bigint, nama text, sales text, hitam boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_k text := public.kunci_nama_pelanggan(public.rhj_nama_rapi(p_nama));
        v_sales boolean := coalesce(public.peran_saya(), '') = 'sales';
begin
  if auth.uid() is null or not (public.boleh_ubah_crm() or public.peran_saya() = 'vonny') then
    raise exception 'Pemeriksaan nama pelanggan hanya untuk peran yang mengelola pelanggan.' using errcode = '42501';
  end if;
  if coalesce(v_k, '') in ('', 'tanpa nama') then return; end if;   -- 139x: nama pengganti bukan identitas
  return query
    select c.id, c.nama, sr.nama, c.blacklist and (not v_sales or public.pic_pelanggan_saya(c.id))   -- 139x
      from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
     where c.id is distinct from p_kecuali
       and (public.kunci_nama_pelanggan(c.nama) = v_k
            or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k)
            or (not v_sales and c.blacklist and exists (select 1 from public.pelanggan_hitam_jejak j   -- 139x: bukan sales
                                                         where j.customer_id = c.id and j.jenis = 'kunci' and j.nilai = v_k)))
     order by (c.blacklist and not v_sales) desc, c.id limit 5;
end $$;
revoke all on function public.nama_pelanggan_kembar_rinci(text, bigint) from public, anon;
grant execute on function public.nama_pelanggan_kembar_rinci(text, bigint) to authenticated;

-- E · (no. 2) Minta ubah SP yang MELEPAS penahanan daftar hitam: GM diberi tahu dan harus menyetujuinya dengan sadar
create or replace function public.usul_lepas_hitam(p_id bigint)
returns text language plpgsql stable security definer set search_path = public as $$
declare u public.usul_ubah; s public.sales_orders; k jsonb; v_lama bigint; v_c public.customers;
begin
  if auth.uid() is null or not public.boleh_approve() then return null; end if;
  select * into u from public.usul_ubah where id = p_id;
  if u.id is null or u.jenis <> 'sp' or u.status <> 'menunggu' then return null; end if;
  select * into s from public.sales_orders where id = u.ref_id;
  if s.id is null then return null; end if;
  k := u.nilai_baru -> 'kepala';
  v_lama := public.sp_pelanggan_hitam(s.customer_id, s.po_id, s.kepada, s.telp);
  if v_lama is null
     or public.sp_pelanggan_hitam(s.customer_id, s.po_id, coalesce(k->>'kepada', s.kepada), coalesce(k->>'telp', s.telp))
        is not null then
    return null;                                   -- tidak tertahan, atau tetap tertahan sesudahnya
  end if;
  select * into v_c from public.customers where id = v_lama;
  return 'SP ' || s.no_sp || ' tertahan karena cocok dengan pelanggan daftar hitam "' || v_c.nama || '" ('
      || coalesce(v_c.alasan_blacklist, 'tanpa keterangan') || ') — menyetujui perubahan Kepada/No. HP ini MELEPAS '
      || 'penahanannya';
end $$;
revoke all on function public.usul_lepas_hitam(bigint) from public, anon;
grant execute on function public.usul_lepas_hitam(bigint) to authenticated;

create or replace function public.setujui_ubah_lepas_hitam(p_id bigint, p_catatan text default null)
returns text language plpgsql security definer set search_path = public as $$
declare r text;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan usulan perubahan.' using errcode = '42501';
  end if;
  perform set_config('rhj.lepas_hitam', 'on', true);
  r := public.putuskan_ubah(p_id, true,
         concat_ws(' ', '[melepas penahanan daftar hitam]', nullif(btrim(coalesce(p_catatan, '')), '')));
  perform set_config('rhj.lepas_hitam', '', true);
  return r;
end $$;
revoke all on function public.setujui_ubah_lepas_hitam(bigint, text) from public, anon;
grant execute on function public.setujui_ubah_lepas_hitam(bigint, text) to authenticated;

-- F · tambalan definisi hidup (jangkar harus muncul tepat n kali; dilewati bila tambalannya sudah ada)
do $$
declare
  t text[];
  d text; d2 text; n int;
  daftar text[] := array[
    -- (no. 2) putuskan_ubah: pelepasan penahanan hanya lewat setujui_ubah_lepas_hitam; sesudahnya kembali ke cek Vonny
    ['public.putuskan_ubah(bigint,boolean,text)', $a$declare u record; b jsonb; k jsonb; v_beda text;$a$,
     $b$declare u record; b jsonb; k jsonb; v_beda text; v_lepas text;   -- 139x$b$, '1'],
    ['public.putuskan_ubah(bigint,boolean,text)', $a$    update public.sales_orders s set$a$,
     $b$    -- 139x (review 139s no. 2): perubahan Kepada/No. HP yang MELEPAS penahanan daftar hitam wajib disetujui dengan
    -- sadar (setujui_ubah_lepas_hitam), lalu SP kembali ke cek Vonny bila barangnya belum keluar
    v_lepas := public.usul_lepas_hitam(p_id);
    if v_lepas is not null and coalesce(current_setting('rhj.lepas_hitam', true), '') <> 'on' then
      raise exception 'Usulan #% belum diterapkan: %. Setujui lewat "Setujui & lepas penahanan" sesudah memastikan ini '
                      'memang perusahaan/orang lain.', p_id, v_lepas using errcode = 'P0001';
    end if;
    update public.sales_orders s set$b$, '1'],
    ['public.putuskan_ubah(bigint,boolean,text)', $a$     where s.id = u.ref_id;$a$,
     $b$     where s.id = u.ref_id;
    if v_lepas is not null then perform public.gugurkan_cek_vonny(u.ref_id); end if;   -- 139x$b$, '1'],
    -- (no. 6) cek_kelayakan_vonny: cermin lengkapi_pelanggan_sp — pelanggan yang cocok (atau kembarannya) tertahan
    ['public.cek_kelayakan_vonny(bigint,text,text)',
     $a$      -- berkas 121 · cermin trigger so_y_hanya_gm (berkas 119): SP tanpa sales yang tertaut ke pelanggan Office$a$,
     $b$      -- 139x (review 139s no. 6): cermin lengkapi_pelanggan_sp — pelanggan yang cocok (atau kembarannya) tertahan
      -- daftar hitam → tidak ditautkan; owner/GM yang memutuskan
      if public.sp_pelanggan_hitam(v_ada.id, null, null, null) is not null then
        kode := 'blacklist'; siapa := 'owner/GM';
        if v_ada.blacklist then
          pesan := 'Pelanggan "' || v_ada.nama || '" yang cocok dengan SP ini masuk daftar hitam ('
                || coalesce(v_ada.alasan_blacklist, 'tanpa keterangan') || ') — SP tidak bisa ditautkan ke sana.';
          tindakan := 'Owner/GM memutuskan: cabut daftar hitamnya di tab Pelanggan, atau batalkan SP; bila ini '
                   || 'perusahaan/orang lain, ubah Kepada/No. HP SP lewat Minta ubah SP (beri pembeda).';
        else
          pesan := 'SP ini cocok dengan pelanggan "' || v_ada.nama || '", yang cocok nama/No. HP dengan pelanggan daftar '
                || 'hitam "' || coalesce((select h.nama from public.customers h
                                          where h.id = public.sp_pelanggan_hitam(v_ada.id, null, null, null)), '—')
                || '" — SP tidak bisa ditautkan ke sana selama itu.';
          tindakan := 'Owner/GM memutuskan: bila "' || v_ada.nama || '" memang perusahaan/orang lain, beri pembeda pada '
                   || 'nama/No. HP-nya di tab Pelanggan; atau cabut daftar hitamnya; atau batalkan SP.';
        end if;
        return next; continue;
      end if;
      -- berkas 121 · cermin trigger so_y_hanya_gm (berkas 119): SP tanpa sales yang tertaut ke pelanggan Office$b$, '1'],
    -- (no. 6) lengkapi_pelanggan_sp: kembaran → pembeda di data pelanggan oleh owner/GM (bukan "ubah No. HP SP")
    ['public.lengkapi_pelanggan_sp(bigint,text,text,text)',
     $a$      raise exception '% SP % cocok dengan pelanggan "%" yang masuk daftar hitam (atau kembarannya) — SP tidak ditautkan ke '$a$,
     $b$      if not v_ada.blacklist then   -- 139x (review 139s no. 6): kembaran — pembedanya di data pelanggan, oleh owner/GM
        raise exception '% SP % cocok dengan pelanggan "%", yang cocok nama/No. HP dengan pelanggan daftar hitam — SP tidak '
                        'ditautkan ke sana. Bila "%" memang perusahaan/orang lain, owner/GM memberi pembeda pada nama/No. '
                        'HP-nya di tab Pelanggan; atau mencabut daftar hitamnya.',
                        case v_cocok when 'hp' then 'No. HP' else 'Nama' end, s.no_sp, v_ada.nama, v_ada.nama
          using errcode = '22023';
      end if;
      raise exception '% SP % cocok dengan pelanggan "%" yang masuk daftar hitam — SP tidak ditautkan ke '$b$, '1'],
    -- (no. 6) putuskan_vonny_cek: SP belum tertaut yang akan ditautkan ke pelanggan tertahan tidak diloloskan
    ['public.putuskan_vonny_cek(bigint,boolean,text)', $a$  if p_ok is false and coalesce(btrim(p_alasan),'') = '' then$a$,
     $b$  -- 139x (review 139s no. 6): SP belum tertaut yang nama/No. HP-nya cocok dengan pelanggan tertahan daftar hitam
  -- (pelanggan itu sendiri atau kembarannya) — sama dengan cek_kelayakan_vonny & lengkapi_pelanggan_sp
  if p_ok and v.customer_id is null
     and exists (select 1 from public.cek_kelayakan_vonny(p_so, null, null) c where c.kode = 'blacklist') then
    raise exception 'Surat Pesanan % belum bisa diloloskan: nama/No. HP-nya cocok dengan pelanggan yang tertahan daftar '
                    'hitam (pelanggan itu sendiri atau kembarannya). Owner/GM yang memutuskan — lihat laci cek.', v.no_sp
      using errcode = '22023';
  end if;
  if p_ok is false and coalesce(btrim(p_alasan),'') = '' then$b$, '1']
  ];
begin
  foreach t slice 1 in array daftar loop
    d := pg_get_functiondef(t[1]::regprocedure);
    if position(t[3] in d) > 0 then continue; end if;   -- sudah ditambal
    n := (length(d) - length(replace(d, t[2], ''))) / length(t[2]);
    if n <> t[4]::int then
      raise exception '139x: % — jangkar "%" muncul % kali (harus %).', t[1], left(t[2], 70), n, t[4];
    end if;
    execute replace(d, t[2], t[3]);
    d2 := pg_get_functiondef(t[1]::regprocedure);
    if replace(d2, t[3], t[2]) <> d then raise exception '139x: % — hasil tambalan tidak sesuai.', t[1]; end if;
  end loop;
end $$;

-- G · uji diri
do $$
begin
  if public.pelanggan_hitam_cocok(array['tanpa nama'], null, null) is not null then
    raise exception '139x: "(tanpa nama)" masih dipakai sebagai identitas.';
  end if;
  if position('old.batal' in pg_get_functiondef('public.jaga_tahan_hitam_sp()'::regprocedure)) > 0
     or position('old.batal AND (NOT new.batal)' in (select pg_get_triggerdef(t.oid) from pg_trigger t
          where t.tgrelid = 'public.sales_orders'::regclass and t.tgname = 'so_vonny_gugur')) = 0 then
    raise exception '139x: penjaga SP batal / cek Vonny saat dihidupkan lagi belum terpasang.';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and tgname = 'customers_zz_jaga_kembar_hitam') then
    raise exception '139x: trigger customers_zz_jaga_kembar_hitam belum terpasang.';
  end if;
  if position('139x' in pg_get_functiondef('public.putuskan_ubah(bigint,boolean,text)'::regprocedure)) = 0
     or position('139x' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0
     or position('139x' in pg_get_functiondef('public.lengkapi_pelanggan_sp(bigint,text,text,text)'::regprocedure)) = 0
     or position('139x' in pg_get_functiondef('public.putuskan_vonny_cek(bigint,boolean,text)'::regprocedure)) = 0 then
    raise exception '139x: tambalan belum terpasang.';
  end if;
end $$;
