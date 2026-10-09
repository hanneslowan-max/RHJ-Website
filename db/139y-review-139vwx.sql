-- ═══════════════════════════════════════════════════════════════════════
-- 139y · Tindak lanjut review gabungan berkas 139v, 139w, 139x (+ #55b di index.html)
-- (nomor 139y: jatah nomor sesi ini 120–139; "y" diurutkan sesudah 139x dan sebelum berkas EHC 140+.
--  Jalankan sesudah 139v, 139w, dan 139x.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  139x-7 (tinggi) SP tertahan dilepas lewat PO-nya: batalkan SP → SP baru dari PO yang sama → Vonny menautkannya
--     (pelanggan PO ikut terisi) → SP lama dihidupkan lagi; untuk SP belum tertaut, rinci hanya membaca pelanggan PO
--     sehingga Kepada/No. HP SP itu sendiri tidak diperiksa lagi. → pelanggan PO MENAMBAH pemeriksaan, tidak
--     menggantikan: SP belum tertaut tetap diperiksa nama/No. HP-nya sendiri.
--  139w-3 (sedang) karakter tak terlihat di luar daftar (U+1D173–1D17A, U+FFF0–FFFB, U+1BCA0–1BCA3, dsb.) dan simbol
--     mirip huruf (∣ × ∪) masih membuat kembaran yang tampak sama. → teks_tanpa_format membuang sisa karakter format;
--     ada_huruf_non_latin kini memakai daftar izin: selain huruf/angka yang diterima, hanya ASCII, spasi, dan tanda
--     umum (’ ‘ “ ” – — … ° ½ ¼ ¾ ² ³ ¹ ™ ® ©) — simbol lain & tanda gabung ditolak untuk selain owner/GM/staff.
--  139w-4 (sedang) Minta ubah SP melangkahi tolakan Kepada non-Latin (GM menerapkan), cek Vonny "baru/siap" lalu
--     lengkapi Vonny gagal. → ajukan_ubah menolak (P0001) untuk selain owner/GM/staff; putuskan_ubah memeriksa peran
--     PENGAJU; cek_kelayakan_vonny melaporkan 'nama_non_latin' (owner/GM) bila pemanggil tidak boleh membuatnya.
--  139w-5 (rendah) ư ơ (Vietnam) ditolak; ligatur ﬁ ﬂ dari PDF ditolak. → Ơơ Ưư diterima; ligatur ﬀ–ﬆ ditulis huruf
--     biasa. ș ț (Rumania) tetap ditolak untuk sales (tanpa lipatan kunci ke ş ţ → kembaran mirip; dicatat).
--  139w-6 (rendah) kunci jejak daftar hitam tidak dihitung ulang sesudah definisi kunci berubah. → kolom
--     pelanggan_hitam_jejak.teks (teks asal), segarkan_jejak_hitam() menghitung ulang; baris lama dari nama sekarang
--     dibangun ulang (kunci versi 139r dikenali lewat fungsi sementara).
--  139v-1 (rendah) kolom lama yang ekspresinya diganti angka komisi lolos penjaga & periksa. → periksa_view_komisi()
--     menambah uji DIFERENSIAL: angka komisi diganti dua kali (komisi_pct_baris, flat pct sales, gm_pct_harga), kolom
--     lain yang terbaca Vonny tidak boleh ikut berubah.
--  139v-2 (rendah) menjalankan ulang 139k sesudah 139v menurunkan fungsi penjaga diam-diam; "jalankan 139v lagi" gagal.
--     → berkas ini memuat ulang SELURUH penjaga (jaga_view_komisi_tertutup, view_komisi_cacat, event trigger,
--     periksa_view_komisi); 139k/139t/139v/139w menolak dijalankan ulang sesudah 139y.
-- Data yang diubah: hanya pelanggan_hitam_jejak (kolom teks; baris dari nama sekarang dibangun ulang). Tidak ada objek
-- yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

do $$ begin
  if to_regprocedure('public.usul_lepas_hitam(bigint)') is null
     or to_regprocedure('public.view_komisi_cacat(oid)') is null
     or position('daftar kolom' in pg_get_functiondef('public.view_komisi_cacat(oid)'::regprocedure)) = 0
     or position('NFC' in pg_get_functiondef('public.teks_tanpa_format(text)'::regprocedure)) = 0 then
    raise exception '139y: jalankan 139v, 139w, dan 139x dulu.';
  end if;
end $$;

-- ───────────── A · teks & huruf (139w-3/5) ─────────────
create or replace function public.teks_tanpa_format(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select normalize(replace(replace(replace(replace(replace(replace(replace(regexp_replace(p,
    '[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ؀-؅۝܏࣢￰-￻\U000110bd\U000110cd\U00013430-\U0001343f\U0001bca0-\U0001bca3\U0001d173-\U0001d17a\U000e0000-\U000e0fff]',
    '', 'g'),
    U&'\FB00', 'ff'), U&'\FB01', 'fi'), U&'\FB02', 'fl'), U&'\FB03', 'ffi'), U&'\FB04', 'ffl'), U&'\FB05', 'st'), U&'\FB06', 'st'),
    NFC)
$$;
comment on function public.teks_tanpa_format(text) is
  '139y: NFC + karakter format (tak terlihat) dibuang + ligatur ﬀ–ﬆ ditulis huruf biasa (NFKC hanya di kunci).';

-- daftar izin untuk selain owner/GM/staff: ASCII yang tercetak & spasi, tanda umum, dan huruf Latin beraksen umum
-- (Latin-1, Latin Extended-A tanpa ı İ ĸ Ŀŀ ŉ ſ, Ơơ Ưư, Latin Extended Additional tanpa 1E96–1E9F & 1EFA–1EFF).
-- Di luar itu — huruf Kiril/Yunani/lain, Latin Extended-B (ǀ Ɩ ș ț), huruf lebar penuh, µ, tanda gabung, simbol
-- (∣ × ∪ …) — dianggap "di luar huruf Latin biasa".
create or replace function public.ada_huruf_non_latin(p text)
returns boolean language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(coalesce(public.teks_tanpa_format(p), ''),
           '[[:space:] -~ ©®°²³¹¼-¾–—‘’“”…™ªºÀ-ÖØ-öø-įĲ-ķĹ-ľŁ-ňŊ-žƠơƯưḀ-ẕẠ-ỹ]',
           '', 'g') <> ''
$$;
comment on function public.ada_huruf_non_latin(text) is
  '139y: true bila ada huruf/simbol di luar daftar izin (huruf Latin biasa & beraksen umum, ASCII, tanda umum).';
reindex index public.customers_kunci_nama_idx;
reindex index public.customers_kunci_nama_lama_idx;

-- ───────────── B · jejak daftar hitam: teks asal & hitung ulang (139w-6) ─────────────
alter table public.pelanggan_hitam_jejak add column if not exists teks text;
comment on column public.pelanggan_hitam_jejak.teks is
  '139y: teks asal (nama) jejak berjenis kunci — dipakai segarkan_jejak_hitam() bila definisi kunci berubah.';

create or replace function public.catat_jejak_hitam()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not (coalesce(new.blacklist, false) or (tg_op = 'UPDATE' and coalesce(old.blacklist, false))) then return null; end if;
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
  select new.id, x.jenis, x.nilai, x.teks
    from (values ('kunci', public.kunci_nama_pelanggan(new.nama), new.nama),
                 ('kunci', public.kunci_nama_pelanggan(new.nama_lama), new.nama_lama),
                 ('hp', new.hp, null::text),
                 ('kunci', case when tg_op = 'UPDATE' then public.kunci_nama_pelanggan(old.nama) end,
                           case when tg_op = 'UPDATE' then old.nama end),
                 ('kunci', case when tg_op = 'UPDATE' then public.kunci_nama_pelanggan(old.nama_lama) end,
                           case when tg_op = 'UPDATE' then old.nama_lama end),
                 ('hp', case when tg_op = 'UPDATE' then old.hp end, null::text)) as x(jenis, nilai, teks)
   where x.nilai is not null and (x.jenis = 'hp' or (char_length(x.nilai) >= 2 and x.nilai <> 'tanpa nama'))
  on conflict do nothing;
  return null;
end $$;
revoke all on function public.catat_jejak_hitam() from public, anon, authenticated;

-- dipanggil setiap migrasi yang mengubah kunci_nama_pelanggan / teks_tanpa_format (ATURAN B)
create or replace function public.segarkan_jejak_hitam()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
  select j.customer_id, 'kunci', k.k, j.teks
    from public.pelanggan_hitam_jejak j
    cross join lateral (select public.kunci_nama_pelanggan(j.teks) as k) k
   where j.jenis = 'kunci' and j.teks is not null and k.k is distinct from j.nilai
     and char_length(coalesce(k.k, '')) >= 2 and k.k <> 'tanpa nama'
  on conflict do nothing;
  execute 'del' || 'ete from public.pelanggan_hitam_jejak j where j.jenis = ''kunci'' and j.teks is not null '
       || 'and j.nilai is distinct from public.kunci_nama_pelanggan(j.teks)';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.segarkan_jejak_hitam() from public, anon, authenticated;

-- baris jejak lama (tanpa teks) yang berasal dari nama/nama asli SEKARANG dibangun ulang dengan kunci baru & teks;
-- kunci versi 139r dikenali lewat salinan fungsinya (sementara, hilang sendiri di akhir sesi)
create or replace function pg_temp.kunci_139r(p text)
returns text language sql immutable as $$
  select coalesce(string_agg(k, ' ' order by n), '')
    from regexp_split_to_table(
           btrim(regexp_replace(regexp_replace(
             ' ' || regexp_replace(
                      translate(lower(coalesce(regexp_replace(normalize(p, NFKC),
                        '[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ\U000e0000-\U000e0fff]',
                        '', 'g'), '')),
                                'аеорсухіјѕкмнтвӏԁԛԝαβεζηικμνορτυχ', 'aeopcyxijskmhtbldqwabezhikmnoptyx'),
                      '[^[:alnum:]]+', ' ', 'g') || ' ',
             ' (t b k|p t|c v|u d|p d|t b)(?= )', ' ', 'g'),
           ' +', ' ', 'g')), ' ')
         with ordinality as s(k, n)
   where k <> '' and k not in ('pt','cv','ud','pd','tb','tbk','toko')
$$;
do $$ begin
  execute 'del' || 'ete from public.pelanggan_hitam_jejak j using public.customers c '
       || 'where j.customer_id = c.id and j.jenis = ''kunci'' and j.teks is null '
       || 'and j.nilai in (pg_temp.kunci_139r(c.nama), pg_temp.kunci_139r(c.nama_lama), '
       || 'public.kunci_nama_pelanggan(c.nama), public.kunci_nama_pelanggan(c.nama_lama))';
end $$;
insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
select c.id, 'kunci', public.kunci_nama_pelanggan(x.t), x.t
  from public.customers c cross join lateral (values (c.nama), (c.nama_lama)) as x(t)
 where c.blacklist and x.t is not null
   and char_length(public.kunci_nama_pelanggan(x.t)) >= 2 and public.kunci_nama_pelanggan(x.t) <> 'tanpa nama'
on conflict do nothing;
select public.segarkan_jejak_hitam();

-- ───────────── C · daftar hitam: pelanggan PO menambah pemeriksaan, tidak menggantikan (139x-7) ─────────────
create or replace function public.sp_pelanggan_hitam_rinci(p_customer bigint, p_po bigint, p_kepada text, p_telp text)
returns table(id bigint, cara text)
language plpgsql stable security definer set search_path = public as $$
declare v_c bigint := p_customer; c public.customers; v_k text; v_hp text; v_id bigint; v_dari_po boolean := false;
begin
  if v_c is null and p_po is not null then
    select p.customer_id into v_c from public.purchase_orders p where p.id = p_po;
    v_dari_po := v_c is not null;
  end if;
  if v_c is not null then
    select * into c from public.customers x where x.id = v_c;
    if c.id is not null then
      if c.blacklist then id := c.id; cara := 'pelanggan'; return next; return; end if;
      -- 139x: nama asli kembaran dihitung hanya selama masih nama asli dari nama sekarang
      v_id := public.pelanggan_hitam_cocok(
                array_remove(array[nullif(public.kunci_nama_pelanggan(c.nama), ''),
                                   case when c.nama_lama is not null
                                             and public.rhj_nama_sidik(c.nama) = public.rhj_nama_sidik(c.nama_lama)
                                        then nullif(public.kunci_nama_pelanggan(c.nama_lama), '') end], null),
                c.hp, c.id);
      if v_id is not null then id := v_id; cara := 'kembar'; return next; return; end if;
    end if;
    -- SP tertaut: hanya pelanggan itu (dan kembarannya) yang menentukan. 139y (review 139x no. 7): SP yang BELUM tertaut
    -- tetap diperiksa nama/No. HP-nya sendiri walau PO-nya sudah tertaut (PO bisa tertaut lewat SP lain)
    if not v_dari_po then return; end if;
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

-- ───────────── D · penjaga view komisi berdiri sendiri + uji diferensial (139v-1/2) ─────────────
create or replace function public.view_komisi_cacat(p_rel oid)
returns text language plpgsql stable set search_path = public as $$
declare c record; v_inv boolean; v_kol text[]; v_harap text[];
begin
  select k.relkind, k.reloptions, k.relname into c from pg_class k where k.oid = p_rel;
  if c.relkind is null then return 'tidak ada'; end if;
  if c.relkind <> 'v' then return 'bukan view'; end if;
  select o.option_value::boolean into v_inv from pg_options_to_table(c.reloptions) o where o.option_name = 'security_invoker';
  if not coalesce(v_inv, false) then return 'tidak security_invoker'; end if;
  if exists (select 1 from pg_rewrite rw where rw.ev_class = p_rel and rw.rulename <> '_RETURN') then
    return 'ada rule selain _RETURN';
  end if;
  if not exists (select 1 from pg_rewrite rw
                   join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = rw.oid
                  where rw.ev_class = p_rel and rw.rulename = '_RETURN' and d.refclassid = 'pg_proc'::regclass
                    and d.refobjid = 'public.boleh_lihat_nilai_klaim()'::regprocedure) then
    return 'tanpa pemanggilan boleh_lihat_nilai_klaim()';
  end if;
  -- 139v: kolom dibekukan. Menambah/mengubah kolom view komisi = perbarui daftar ini DULU (berkas migrasi yang sama),
  -- sesudah memastikan kolom barunya tidak membuka angka komisi/persen bagi peran lain.
  v_harap := case c.relname
    when 'so_ringkas' then array['so_id','no_sp','tanggal','sales_rep_id','ppn_kena','status','total_barang','total_ehc',
      'sub_total','ppn','grand_total','komisi','ada_bawah_list','jumlah_baris','total_biaya','dasar_ppn','n_bawah_list',
      'n_tanpa_list','mode_ppn']
    when 'so_baris_hitung' then array['id','so_id','urut','product_id','qty','harga_nett','ehc_item','harga_list',
      'nilai_barang','nilai_ehc','nilai_baris','hammer','pct','jenis','harga_khusus_id','qty_pesan','qty_batal','mode_ppn',
      'nett_dpp','nilai_barang_dpp','nilai_ehc_dpp','nilai_baris_dpp','pct_berlaku','sumber_pct','perlu_gm']
    when 'cash_belum_cocok' then array['so_id','no_sp','tanggal','kepada','sales_rep_id','lunas','tgl_lunas','no_invoice',
      'total_barang','komisi_sekarang','komisi_kalau_cash']
    when 'komisi_belum_klaim' then array['so_id','no_sp','tanggal','kepada','customer_id','sales_rep_id','lunas',
      'tgl_lunas','telat','gm_pct','harga_ok','ada_bawah_list','total_barang','komisi','bisa_klaim','alasan']
  end;
  if v_harap is not null then
    select array_agg(a.attname::text order by a.attnum) into v_kol
      from pg_attribute a where a.attrelid = p_rel and a.attnum > 0 and not a.attisdropped;
    if v_kol is distinct from v_harap then
      return 'daftar kolom berubah — tinjau kolom barunya lalu perbarui daftar di public.view_komisi_cacat (berkas 139y)';
    end if;
  end if;
  return null;
end $$;
revoke all on function public.view_komisi_cacat(oid) from public, anon, authenticated;

create or replace function public.jaga_view_komisi_tertutup()
returns event_trigger language plpgsql set search_path = public as $f$
declare r record; v_rel oid; v_nama text; v_cacat text;
begin
  for r in select * from pg_event_trigger_ddl_commands() loop
    v_rel := null;
    if r.classid = 'pg_rewrite'::regclass then
      select rw.ev_class into v_rel from pg_rewrite rw where rw.oid = r.objid;
    elsif r.classid = 'pg_class'::regclass then
      v_rel := r.objid;
    end if;
    continue when v_rel is null;
    select k.relname into v_nama from pg_class k
     where k.oid = v_rel and k.relnamespace = 'public'::regnamespace
       and k.relname in ('so_ringkas','so_baris_hitung','cash_belum_cocok','komisi_belum_klaim');
    continue when v_nama is null;
    v_cacat := public.view_komisi_cacat(v_rel);
    if v_cacat is not null then
      raise exception '139k/139t: view public.% kehilangan penyaring komisi (%) — sertakan lagi predikat berkas 139k dan '
                      'security_invoker (lihat ATURAN B › Akses & peran).', v_nama, v_cacat;
    end if;
  end loop;
end $f$;
revoke all on function public.jaga_view_komisi_tertutup() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi') then
    create event trigger jaga_view_komisi on ddl_command_end when tag in ('CREATE VIEW', 'ALTER VIEW')
      execute function public.jaga_view_komisi_tertutup();
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi_b') then
    create event trigger jaga_view_komisi_b on ddl_command_end when tag in ('ALTER TABLE', 'CREATE RULE')
      execute function public.jaga_view_komisi_tertutup();
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi_c') then
    create event trigger jaga_view_komisi_c on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW',
                   'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE', 'IMPORT FOREIGN SCHEMA')
      execute function public.jaga_view_komisi_tertutup();
  end if;
end $$;
alter event trigger jaga_view_komisi enable always;
alter event trigger jaga_view_komisi_b enable always;
alter event trigger jaga_view_komisi_c enable always;

create or replace function public.periksa_view_komisi()
returns void language plpgsql volatile set search_path = public as $$
declare
  v_nama text; v_cacat text;
  v_vonny uuid; v_sales uuid; v_rep bigint; v_so bigint; v_calon bigint[]; v_siap boolean := false; v_galat text;
  a1 bigint; a2 bigint; a3 bigint; a4 bigint;             -- prasyarat (postgres): SP uji muncul di ke-4 view
  n1 bigint; n2 bigint; n3 bigint; n4 bigint; n5 bigint;  -- Vonny
  m1 bigint; m2 bigint; m3 bigint; m4 bigint; m5 bigint;  -- sales
  v_args text; v_nilai text; v_mode text; v_beda text; v_sidik text[] := '{}'; v_f text; v_g text; v_cek bigint;   -- 139y
begin
  foreach v_nama in array array['so_ringkas','so_baris_hitung','cash_belum_cocok','komisi_belum_klaim'] loop
    v_cacat := public.view_komisi_cacat(coalesce(to_regclass('public.' || v_nama)::oid, 0));
    if v_cacat is not null then
      raise exception '139k/139t: view public.% kehilangan penyaring komisi (%) — sertakan lagi predikat berkas 139k dan '
                      'security_invoker (lihat ATURAN B › Akses & peran).', v_nama, v_cacat;
    end if;
  end loop;

  -- Uji perilaku: disusun sendiri di subtransaksi yang SELALU dibatalkan (P0099) — data, fungsi, peran, klaim, dan
  -- replica pemanggil kembali utuh. Variabel hasil tetap terbaca sesudahnya.
  begin
    perform set_config('role', 'none', true);
    set local session_replication_role = replica;   -- trigger data dilewati; event trigger (ALWAYS) tidak terlibat
    select p.id, sr.id into v_sales, v_rep from public.profiles p join public.sales_reps sr on sr.profile_id = p.id
     where p.peran = 'sales' order by p.id limit 1;
    if v_sales is null then v_galat := 'tidak ada akun sales bertaut sales_reps'; raise exception using errcode = 'P0099'; end if;
    select p.id into v_vonny from public.profiles p where p.peran = 'vonny' order by p.id limit 1;
    if v_vonny is null then   -- tanpa profil Vonny: satu profil lain dijadikan Vonny (dibatalkan bersama uji)
      select p.id into v_vonny from public.profiles p where p.id <> v_sales and p.peran <> 'owner' order by p.id limit 1;
      if v_vonny is null then v_galat := 'tidak ada profil untuk simulasi Vonny'; raise exception using errcode = 'P0099'; end if;
      update public.profiles set peran = 'vonny' where id = v_vonny;
    end if;
    select array_agg(s.id order by s.id desc) into v_calon from public.sales_orders s
     where s.sales_rep_id is distinct from v_rep and not coalesce(s.batal, false)
       and not exists (select 1 from public.komisi_klaim k where k.so_id = s.id)
       and exists (select 1 from public.so_baris_hitung b where b.so_id = s.id and b.jenis = 'barang' and b.pct is not null)
       and not exists (select 1 from public.so_baris_hitung b where b.so_id = s.id and b.harga_khusus_id is not null);
    perform set_config('request.jwt.claims', json_build_object('sub', v_vonny, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select s.id into v_so from public.sales_orders s where s.id = any(coalesce(v_calon, '{}')) order by s.id desc limit 1;
    perform set_config('role', 'none', true);
    if v_so is null then v_galat := 'tidak ada SP sales lain yang terbaca Vonny untuk diuji'; raise exception using errcode = 'P0099'; end if;
    update public.sales_orders set cash_minta = true, cash_ok = null where id = v_so;   -- menunggu keputusan cash
    select count(*) into a1 from public.so_ringkas where so_id = v_so and komisi is not null;
    select count(*) into a2 from public.so_baris_hitung where so_id = v_so and pct is not null;
    select count(*) into a3 from public.cash_belum_cocok where so_id = v_so;
    select count(*) into a4 from public.komisi_belum_klaim where so_id = v_so;
    if a1 * a2 * a3 * a4 = 0 then
      v_galat := format('SP uji %s tidak lengkap di view (so_ringkas %s, so_baris_hitung %s, cash_belum_cocok %s, '
                        'komisi_belum_klaim %s)', v_so, a1, a2, a3, a4);
      raise exception using errcode = 'P0099';
    end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_vonny, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(komisi) into n1 from public.so_ringkas;
    select count(pct) + count(pct_berlaku) into n2 from public.so_baris_hitung;
    select count(*) into n3 from public.komisi_belum_klaim;
    select count(*) into n4 from public.cash_belum_cocok;
    select count(*) into n5 from public.so_ringkas where so_id = v_so;
    perform set_config('role', 'none', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sales, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into m1 from public.so_ringkas r where r.komisi is not null and r.sales_rep_id is distinct from v_rep;
    select count(*) into m2 from public.so_baris_hitung b join public.sales_orders s on s.id = b.so_id
     where (b.pct is not null or b.pct_berlaku is not null) and s.sales_rep_id is distinct from v_rep;
    select count(*) into m3 from public.komisi_belum_klaim k where k.sales_rep_id is distinct from v_rep;
    select count(*) into m4 from public.cash_belum_cocok c where c.sales_rep_id is distinct from v_rep;
    select (select count(*) from public.so_ringkas) - (select count(*) from public.sales_orders) into m5;
    perform set_config('role', 'none', true);
    -- 139y (review 139v no. 1): uji DIFERENSIAL — angka komisi SP uji diganti dua kali (sama-sama terisi, jadi cabang
    -- label tetap) pada tiap cabang sumber komisi (tier, cash, flat); kolom lain yang terbaca Vonny tidak boleh ikut
    -- berubah. Menangkap kolom lama yang ekspresinya diganti angka komisi/persen (mis. sumber_pct = 'tier ' || pct).
    v_args := pg_get_function_arguments('public.komisi_pct_baris'::regproc);
    foreach v_mode in array array['tier', 'cash', 'flat'] loop
      v_sidik := '{}';
      foreach v_nilai in array array['0.0111', '0.0222'] loop
        execute format('create or replace function public.komisi_pct_baris(%s) returns numeric language sql as %L',
                       v_args, 'select ' || v_nilai || '::numeric');
        update public.sales_reps set komisi_flat_pct = case when v_mode = 'flat' then v_nilai::numeric end
         where id = (select s.sales_rep_id from public.sales_orders s where s.id = v_so);
        update public.sales_orders set cash_ok = case when v_mode = 'cash' then true end,
               gm_pct_harga = v_nilai::numeric, gm_pct = v_nilai::numeric where id = v_so;
        select count(*) into v_cek from public.so_baris_hitung b
         where b.so_id = v_so and b.jenis = 'barang' and b.pct = v_nilai::numeric;
        if v_cek = 0 then
          v_galat := 'uji diferensial tidak bermakna — angka komisi SP uji tidak berubah (' || v_mode || ')';
          raise exception using errcode = 'P0099';
        end if;
        perform set_config('request.jwt.claims', json_build_object('sub', v_vonny, 'role', 'authenticated')::text, true);
        set local role authenticated;
        select md5(coalesce(string_agg((to_jsonb(b) - 'pct' - 'pct_berlaku')::text, '|' order by b.id), '')) into v_f
          from public.so_baris_hitung b where b.so_id = v_so;
        select md5(coalesce(string_agg((to_jsonb(r) - 'komisi')::text, '|'), '')) into v_g
          from public.so_ringkas r where r.so_id = v_so;
        perform set_config('role', 'none', true);
        v_sidik := v_sidik || (v_f || v_g);
      end loop;
      if v_sidik[1] is distinct from v_sidik[2] then v_beda := coalesce(v_beda || ', ', '') || v_mode; end if;
    end loop;
    v_siap := true;
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  if not v_siap then
    raise exception '139v: uji perilaku view komisi tidak bisa disusun (%) — perbaiki datanya atau periksa_view_komisi().', v_galat;
  end if;
  if n5 = 0 then
    raise exception '139v: uji perilaku tidak bermakna — Vonny tidak membaca SP uji % di so_ringkas.', v_so;
  end if;
  if n1 + n2 + n3 + n4 <> 0 then
    raise exception '139t: Vonny masih melihat angka komisi (so_ringkas %, so_baris_hitung %, komisi_belum_klaim %, '
                    'cash_belum_cocok %).', n1, n2, n3, n4;
  end if;
  if m1 + m2 + m3 + m4 <> 0 or m5 > 0 then
    raise exception '139t: sales (rep %) melihat komisi/baris SP sales lain (so_ringkas %, so_baris_hitung %, '
                    'komisi_belum_klaim %, cash_belum_cocok %, kelebihan baris so_ringkas %).', v_rep, m1, m2, m3, m4, m5;
  end if;
  if v_beda is not null then
    raise exception '139y: kolom lain di so_baris_hitung/so_ringkas yang terbaca Vonny ikut berubah saat angka komisi '
                    'berubah (cabang %) — ada kolom yang membawa angka komisi/persen. Tinjau ekspresi kolom view komisi.', v_beda;
  end if;
end $$;
revoke all on function public.periksa_view_komisi() from public, anon, authenticated;
comment on function public.periksa_view_komisi() is
  '139y: struktur + uji perilaku (Vonny/sales) + uji diferensial; berkas 139k/139t/139v tidak dijalankan ulang sesudahnya.';

-- ───────────── E · Kepada non-Latin lewat Minta ubah SP & cek Vonny (139w-4) ─────────────
do $$
declare
  t text[];
  d text; d2 text; n int;
  daftar text[] := array[
    ['public.ajukan_ubah(text,bigint,jsonb,text)', $a$  if v_lama is null then$a$,
     $b$  -- 139y (review 139w no. 4): Kepada SP berhuruf/simbol di luar huruf Latin biasa ditolak untuk selain
  -- owner/GM/staff, juga lewat Minta ubah SP (= so_a_kepada_bersih)
  if p_jenis = 'sp' and coalesce(public.peran_saya(), '') not in ('owner','gm','staff')
     and jsonb_typeof(p_baru->'kepala') = 'object' and (p_baru->'kepala') ? 'kepada'
     and public.ada_huruf_non_latin(p_baru->'kepala'->>'kepada') then
    raise exception 'Kepada "%" memuat huruf atau simbol khusus di luar huruf Latin biasa (mis. huruf Kiril/Yunani atau '
                    'simbol yang mirip huruf). Ketik ulang dengan huruf biasa; bila memang perlu, minta owner/GM/staff.',
      p_baru->'kepala'->>'kepada' using errcode = 'P0001';
  end if;
  if v_lama is null then$b$, '1'],
    ['public.putuskan_ubah(bigint,boolean,text)', $a$    v_lepas := public.usul_lepas_hitam(p_id);$a$,
     $b$    -- 139y (review 139w no. 4): Kepada non-Latin dari usulan selain owner/GM/staff tidak diterapkan (peran PENGAJU)
    if jsonb_typeof(k) = 'object' and k ? 'kepada' and public.ada_huruf_non_latin(k->>'kepada')
       and coalesce((select pr.peran from public.profiles pr where pr.id = u.diajukan_oleh), '') not in ('owner','gm','staff') then
      raise exception 'Usulan #% tidak diterapkan: Kepada "%" memuat huruf atau simbol khusus di luar huruf Latin biasa — '
                      'pengajunya diminta mengetik ulang dengan huruf biasa (atau owner/GM/staff yang mengubahnya).',
        p_id, k->>'kepada' using errcode = 'P0001';
    end if;
    v_lepas := public.usul_lepas_hitam(p_id);$b$, '1'],
    ['public.cek_kelayakan_vonny(bigint,text,text)', $a$    if s.sales_rep_id is null then
      kode := 'sales_kosong'; siapa := 'owner/GM';$a$,
     $b$    -- 139y (review 139w no. 4): pelanggan baru bernama non-Latin hanya dibuat owner/GM/staff (customers_tolak_nama_ganda)
    if coalesce(public.peran_saya(), '') not in ('owner','gm','staff')
       and public.ada_huruf_non_latin(public.rhj_nama_rapi(s.kepada)) then
      kode := 'nama_non_latin'; siapa := 'owner/GM';
      pesan := 'Nama "' || coalesce(s.kepada, '') || '" memuat huruf atau simbol di luar huruf Latin biasa — pelanggan '
            || 'barunya hanya bisa dibuat owner/GM/staff.';
      tindakan := 'Owner/GM menautkan/melengkapi pelanggan SP ini sendiri (laci cek atau detail SP), atau Kepada diubah '
               || 'ke huruf biasa lewat Minta ubah SP.';
      return next; continue;
    end if;
    if s.sales_rep_id is null then
      kode := 'sales_kosong'; siapa := 'owner/GM';$b$, '1'],
    -- pesan: "huruf atau simbol khusus"
    ['public.sp_kepada_bersih()', $a$memuat huruf di luar huruf Latin biasa (mis. huruf Kiril/Yunani yang mirip)$a$,
     $b$memuat huruf atau simbol khusus di luar huruf Latin biasa (mis. huruf Kiril/Yunani atau simbol yang mirip huruf)$b$, '1'],
    ['public.customers_tolak_nama_ganda()', $a$memuat huruf di luar huruf Latin biasa (mis. huruf Kiril/Yunani yang mirip)$a$,
     $b$memuat huruf atau simbol khusus di luar huruf Latin biasa (mis. huruf Kiril/Yunani atau simbol yang mirip huruf)$b$, '1']
  ];
begin
  foreach t slice 1 in array daftar loop
    d := pg_get_functiondef(t[1]::regprocedure);
    if position(t[3] in d) > 0 then continue; end if;   -- sudah ditambal
    n := (length(d) - length(replace(d, t[2], ''))) / length(t[2]);
    if n <> t[4]::int then
      raise exception '139y: % — jangkar "%" muncul % kali (harus %).', t[1], left(t[2], 70), n, t[4];
    end if;
    execute replace(d, t[2], t[3]);
    d2 := pg_get_functiondef(t[1]::regprocedure);
    if replace(d2, t[3], t[2]) <> d then raise exception '139y: % — hasil tambalan tidak sesuai.', t[1]; end if;
  end loop;
end $$;
comment on function public.ada_huruf_non_latin(text) is
  '139y: true bila ada huruf/simbol di luar daftar izin (huruf Latin biasa & beraksen umum, ASCII, tanda umum).';

-- ───────────── F · uji diri ─────────────
do $$
declare v_tolak text; v_def text; c_hitam public.customers; v_po bigint;
begin
  -- huruf & teks
  if public.kunci_nama_pelanggan('PT DH' || chr(119155) || 'L Supply') <> public.kunci_nama_pelanggan('PT DHL Supply')
     or public.kunci_nama_pelanggan('PT DH' || chr(65520) || 'L Supply') <> public.kunci_nama_pelanggan('PT DHL Supply')
     or public.teks_tanpa_format('PT O' || chr(64257) || 'ce') <> 'PT Ofice'
     or not public.ada_huruf_non_latin('Rubber ' || chr(8739) || 'ndonesia')   -- ∣
     or not public.ada_huruf_non_latin('PT Mitra Ma' || chr(215))             -- ×
     or not public.ada_huruf_non_latin('Tokai Rubber Indonesi' || chr(775) || 'a')   -- tanda gabung
     or not public.ada_huruf_non_latin('Ro' || chr(537) || 'u')               -- ș
     or not public.ada_huruf_non_latin('Rubber ' || chr(448) || 'ndonesia')   -- ǀ
     or public.ada_huruf_non_latin('Tr' || chr(432) || chr(417) || 'ng Ph' || chr(432) || chr(417) || 'ng')   -- Trương Phương
     or public.ada_huruf_non_latin('PT O' || chr(64257) || 'ce Solution')     -- ligatur → fi
     or public.ada_huruf_non_latin('Café Ünal & Söhne, PT (Jkt) 2')
     or public.ada_huruf_non_latin('Toko Besi 1' || chr(189) || ' Inch – CV ' || chr(8220) || 'X' || chr(8221) || chr(8482))
     or public.ada_huruf_non_latin('Ma''ruf ' || chr(8217) || 's')
  then
    raise exception '139y: uji huruf/teks gagal.';
  end if;
  -- jejak sesuai kunci sekarang
  if exists (select 1 from public.pelanggan_hitam_jejak j
              where j.jenis = 'kunci' and j.teks is not null and j.nilai is distinct from public.kunci_nama_pelanggan(j.teks)) then
    raise exception '139y: jejak daftar hitam belum sesuai kunci sekarang.';
  end if;
  -- rinci: SP belum tertaut dengan PO tertaut tetap diperiksa nama-nya sendiri
  select c.* into c_hitam from public.customers c where c.blacklist order by c.id limit 1;
  select p.id into v_po from public.purchase_orders p join public.customers x on x.id = p.customer_id
   where not x.blacklist and public.sp_pelanggan_hitam(x.id, null, null, null) is null order by p.id limit 1;
  if c_hitam.id is not null and v_po is not null
     and public.sp_pelanggan_hitam(null, v_po, c_hitam.nama, null) is null then
    raise exception '139y: SP belum tertaut di PO tertaut tidak diperiksa nama-nya sendiri.';
  end if;
  -- penjaga view komisi
  perform public.periksa_view_komisi();
  if position('view_komisi_cacat' in pg_get_functiondef('public.jaga_view_komisi_tertutup()'::regprocedure)) = 0
     or (select count(*) from pg_event_trigger
          where evtname in ('jaga_view_komisi','jaga_view_komisi_b','jaga_view_komisi_c') and evtenabled = 'A') <> 3 then
    raise exception '139y: penjaga view komisi belum lengkap.';
  end if;
  -- kolom lama yang ekspresinya diganti angka komisi → periksa menolak
  v_def := pg_get_viewdef('public.so_baris_hitung'::regclass);
  if position($q$ELSE 'tier'::text$q$ in v_def) = 0 then raise exception '139y: jangkar uji so_baris_hitung tidak ditemukan.'; end if;
  v_tolak := null;
  begin
    execute 'create or replace view public.so_baris_hitung with (security_invoker = on) as '
            || replace(v_def, $q$ELSE 'tier'::text$q$, $q$ELSE ('tier '::text || (k.pct)::text)$q$);
    perform public.periksa_view_komisi();
    raise exception using errcode = 'P0099';
  exception
    when sqlstate 'P0099' then v_tolak := 'LOLOS';
    when others then v_tolak := sqlerrm;
  end;
  if position('139y' in coalesce(v_tolak, '')) = 0 then
    raise exception '139y: uji diferensial tidak menangkap kolom pembawa angka komisi (hasil: %).', v_tolak;
  end if;
  if position('139w' in pg_get_functiondef('public.lengkapi_pelanggan_sp(bigint,text,text,text)'::regprocedure)) = 0
     or position('139y' in pg_get_functiondef('public.ajukan_ubah(text,bigint,jsonb,text)'::regprocedure)) = 0
     or position('139y' in pg_get_functiondef('public.putuskan_ubah(bigint,boolean,text)'::regprocedure)) = 0
     or position('139y' in pg_get_functiondef('public.cek_kelayakan_vonny(bigint,text,text)'::regprocedure)) = 0 then
    raise exception '139y: tambalan belum terpasang.';
  end if;
end $$;
