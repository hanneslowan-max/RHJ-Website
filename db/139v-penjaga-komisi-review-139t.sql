-- ═══════════════════════════════════════════════════════════════════════
-- 139v · Tindak lanjut review berkas 139t (penjaga view komisi, temuan keamanan #1)
-- (nomor 139v: jatah nomor sesi ini 120–139; "v" diurutkan sesudah 139u dan sebelum berkas EHC 140+.
--  Jalankan sesudah 139k dan 139t.)
--
-- Temuan review yang dikonfirmasi di DEV (semua rendah; hanya bisa dipicu DDL pemegang akun postgres, bukan pengguna):
--  1/5. Kedua event trigger (mode 'O') tidak menyala saat session_replication_role = replica — pola yang dipakai
--     migrasi repo ini sendiri (126, 128, 130, 135). → ENABLE ALWAYS.
--  2/6. view_komisi_cacat menerima ketergantungan dari rule MANA SAJA pada view (rule tambahan yang menyebut
--     boleh_lihat_nilai_klaim() cukup untuk meloloskan _RETURN tanpa predikat), dan kolom tambahan yang membuka
--     angka mentah (mis. `k.pct AS pct_mentah`) tetap lolos karena ketergantungannya masih ada. → hanya rule _RETURN
--     yang dihitung, rule lain pada ke-4 view ditolak, dan **daftar kolom ke-4 view dibekukan** (kolom baru/berubah
--     ditolak sampai daftarnya diperbarui di fungsi ini — perubahan yang ditinjau).
--  2. Uji perilaku periksa_view_komisi() bergantung pada data yang kebetulan ada (tanpa profil Vonny → dilewati
--     diam-diam; tanpa SP yang menunggu keputusan cash → cash_belum_cocok tidak teruji). → uji dibuat mandiri di
--     dalam subtransaksi yang selalu dibatalkan: satu SP sales lain dijadikan menunggu keputusan cash, profil Vonny
--     disimulasikan bila tidak ada; gagal keras bila uji tidak bisa disusun.
--  3/7. CREATE TABLE / CTAS / SELECT INTO / MATERIALIZED VIEW / FOREIGN TABLE (juga lewat rename) dengan nama ke-4
--     view tidak dijaga — relasi seperti itu tanpa RLS dan terbaca anon. → event trigger ketiga jaga_view_komisi_c.
--  4. periksa_view_komisi() meninggalkan pemanggil sebagai session user (RESET ROLE sesi). → semua perubahan peran,
--     klaim, dan replica terjadi di dalam subtransaksi yang dibatalkan, jadi keadaan pemanggil kembali utuh.
--  Sisa yang diterima (dicatat di HANDOFF): mengganti ISI fungsi predikat (boleh_lihat_nilai_klaim, peran_saya,
--  sales_rep_saya) tidak dijaga event trigger — hanya tertangkap uji perilaku periksa_view_komisi().
-- Tidak ada data yang diubah (uji perilaku selalu dibatalkan); tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- 00 · berkas ini sudah disusul 139y: menjalankannya ulang sendirian menurunkan fungsi yang diperbarui berkas sesudahnya
--      (review 139v no. 2). Menjalankan ulang seluruh rantai 138 → 139y berurutan: `set rhj.ulang_rantai = 'on';` dulu.
do $$ begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is not null
     and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
    raise exception '139v: berkas ini sudah disusul 139y — jangan dijalankan ulang sendirian (jalankan ulang seluruh rantai '
                    '138 → 139y berurutan sesudah set rhj.ulang_rantai = ''on'').';
  end if;
end $$;

-- A · penjaga struktur: hanya rule _RETURN, kolom dibekukan
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
      return 'daftar kolom berubah — tinjau kolom barunya lalu perbarui daftar di public.view_komisi_cacat (berkas 139v)';
    end if;
  end if;
  return null;
end $$;
revoke all on function public.view_komisi_cacat(oid) from public, anon, authenticated;

-- B · event trigger: menyala juga di mode replica; relasi bukan-view dengan nama view komisi ditolak
alter event trigger jaga_view_komisi enable always;
alter event trigger jaga_view_komisi_b enable always;
do $$ begin
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi_c') then
    create event trigger jaga_view_komisi_c on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW',
                   'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE', 'IMPORT FOREIGN SCHEMA')
      execute function public.jaga_view_komisi_tertutup();
  end if;
end $$;
alter event trigger jaga_view_komisi_c enable always;

-- C · periksa_view_komisi(): struktur + uji perilaku mandiri (dipanggil di akhir setiap migrasi yang menyentuh view komisi)
create or replace function public.periksa_view_komisi()
returns void language plpgsql volatile set search_path = public as $$
declare
  v_nama text; v_cacat text;
  v_vonny uuid; v_sales uuid; v_rep bigint; v_so bigint; v_calon bigint[]; v_siap boolean := false; v_galat text;
  a1 bigint; a2 bigint; a3 bigint; a4 bigint;             -- prasyarat (postgres): SP uji muncul di ke-4 view
  n1 bigint; n2 bigint; n3 bigint; n4 bigint; n5 bigint;  -- Vonny
  m1 bigint; m2 bigint; m3 bigint; m4 bigint; m5 bigint;  -- sales
begin
  foreach v_nama in array array['so_ringkas','so_baris_hitung','cash_belum_cocok','komisi_belum_klaim'] loop
    v_cacat := public.view_komisi_cacat(coalesce(to_regclass('public.' || v_nama)::oid, 0));
    if v_cacat is not null then
      raise exception '139k/139t: view public.% kehilangan penyaring komisi (%) — sertakan lagi predikat berkas 139k dan '
                      'security_invoker (lihat ATURAN B › Akses & peran).', v_nama, v_cacat;
    end if;
  end loop;

  -- Uji perilaku (139v): disusun sendiri di subtransaksi yang SELALU dibatalkan (P0099) — data, peran, klaim, dan
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
    -- SP uji: milik sales lain, belum diklaim, punya baris barang berpersen (terbaca Vonny — dipilih di bawah)
    select array_agg(s.id order by s.id desc) into v_calon from public.sales_orders s
     where s.sales_rep_id is distinct from v_rep and not coalesce(s.batal, false)
       and not exists (select 1 from public.komisi_klaim k where k.so_id = s.id)
       and exists (select 1 from public.so_baris_hitung b where b.so_id = s.id and b.jenis = 'barang' and b.pct is not null);
    perform set_config('request.jwt.claims', json_build_object('sub', v_vonny, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select s.id into v_so from public.sales_orders s where s.id = any(coalesce(v_calon, '{}')) order by s.id desc limit 1;
    perform set_config('role', 'none', true);
    if v_so is null then v_galat := 'tidak ada SP sales lain yang terbaca Vonny untuk diuji'; raise exception using errcode = 'P0099'; end if;
    update public.sales_orders set cash_minta = true, cash_ok = null where id = v_so;   -- menunggu keputusan cash
    -- prasyarat: tanpa penyaring, SP uji membawa angka di ke-4 view
    select count(*) into a1 from public.so_ringkas where so_id = v_so and komisi is not null;
    select count(*) into a2 from public.so_baris_hitung where so_id = v_so and pct is not null;
    select count(*) into a3 from public.cash_belum_cocok where so_id = v_so;
    select count(*) into a4 from public.komisi_belum_klaim where so_id = v_so;
    if a1 * a2 * a3 * a4 = 0 then
      v_galat := format('SP uji %s tidak lengkap di view (so_ringkas %s, so_baris_hitung %s, cash_belum_cocok %s, '
                        'komisi_belum_klaim %s)', v_so, a1, a2, a3, a4);
      raise exception using errcode = 'P0099';
    end if;
    -- Vonny (bukan peran berhak): nol angka komisi di ke-4 view, padahal SP uji terbaca
    perform set_config('request.jwt.claims', json_build_object('sub', v_vonny, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(komisi) into n1 from public.so_ringkas;
    select count(pct) + count(pct_berlaku) into n2 from public.so_baris_hitung;
    select count(*) into n3 from public.komisi_belum_klaim;
    select count(*) into n4 from public.cash_belum_cocok;
    select count(*) into n5 from public.so_ringkas where so_id = v_so;
    perform set_config('role', 'none', true);
    -- sales: tidak ada angka/baris SP sales lain
    perform set_config('request.jwt.claims', json_build_object('sub', v_sales, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into m1 from public.so_ringkas r where r.komisi is not null and r.sales_rep_id is distinct from v_rep;
    select count(*) into m2 from public.so_baris_hitung b join public.sales_orders s on s.id = b.so_id
     where (b.pct is not null or b.pct_berlaku is not null) and s.sales_rep_id is distinct from v_rep;
    select count(*) into m3 from public.komisi_belum_klaim k where k.sales_rep_id is distinct from v_rep;
    select count(*) into m4 from public.cash_belum_cocok c where c.sales_rep_id is distinct from v_rep;
    select (select count(*) from public.so_ringkas) - (select count(*) from public.sales_orders) into m5;
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
end $$;
revoke all on function public.periksa_view_komisi() from public, anon, authenticated;

-- D · uji diri (semua percobaan DDL dibatalkan)
do $$
declare v_peran text := current_setting('role'); v_tolak text; t record;
begin
  perform public.periksa_view_komisi();
  if current_setting('role') is distinct from v_peran then
    raise exception '139v: periksa_view_komisi() mengubah peran pemanggil (% → %).', v_peran, current_setting('role');
  end if;
  if (select count(*) from pg_event_trigger
       where evtname in ('jaga_view_komisi','jaga_view_komisi_b','jaga_view_komisi_c') and evtenabled = 'A') <> 3 then
    raise exception '139v: event trigger jaga_view_komisi / _b / _c belum ENABLE ALWAYS.';
  end if;
  for t in select * from (values
      ('replica + reset security_invoker',
       'set local session_replication_role = replica; alter table public.so_ringkas reset (security_invoker)'),
      ('rule tambahan',
       'create rule zz_uji_139v as on update to public.komisi_belum_klaim do instead nothing'),
      ('ganti nama kolom',
       'alter view public.cash_belum_cocok rename column kepada to kepada_uji'),
      ('CTAS dengan nama view komisi',
       'alter view public.cash_belum_cocok rename to zz_uji_cbc; create table public.cash_belum_cocok as select 1 as x'),
      ('materialized view lewat rename',
       'create materialized view public.zz_uji_mv as select 1 as x with no data; '
       'alter view public.komisi_belum_klaim rename to zz_uji_kbk; alter materialized view public.zz_uji_mv rename to komisi_belum_klaim')
    ) as u(nama, sql) loop
    v_tolak := null;
    begin
      execute t.sql;
      raise exception using errcode = 'P0099';
    exception
      when sqlstate 'P0099' then v_tolak := 'LOLOS';
      when others then v_tolak := sqlerrm;
    end;
    if v_tolak is null or position('kehilangan penyaring komisi' in v_tolak) = 0 then
      raise exception '139v: penjaga tidak menolak "%" (hasil: %).', t.nama, v_tolak;
    end if;
  end loop;
  -- DDL sah tetap lolos: buat ulang view dengan definisinya sendiri, tabel lain
  begin
    execute 'create or replace view public.cash_belum_cocok with (security_invoker = on) as '
            || pg_get_viewdef('public.cash_belum_cocok'::regclass);
    execute 'create table public.zz_uji_139v (id int)';
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
end $$;
