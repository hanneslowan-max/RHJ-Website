-- ═══════════════════════════════════════════════════════════════════════
-- 139z · Tindak lanjut review berkas 139y (+ index.html)
-- (nomor 139z: jatah nomor sesi ini 120–139; "z" diurutkan sesudah 139y dan sebelum berkas EHC 140+.
--  Jalankan sesudah 139y.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  2. (sedang) spasi sempit (U+200A, U+2009, U+202F, …) di tengah kata: Kepada "PT Jumbo Muara Teh<U+200A>nik" lolos
--     daftar hitam & cek pelanggan sales lain (kunci "teh nik"), tampil nyaris sama. → teks_tanpa_format menulis semua
--     spasi khusus sebagai spasi biasa (celahnya jadi terlihat); daftar izin ada_huruf_non_latin hanya menerima spasi
--     biasa, TAB, baris baru, dan spasi tak terputus (U+001C–001F dll. ditolak, sama dengan layar).
--  3/8. (sedang) Minta ubah SP: Kepada yang TIDAK diubah ikut diperiksa — sales tidak bisa mengajukan perubahan apa pun
--     pada SP ber-Kepada simbol (ditulis owner/GM/staff atau data lama), usulan yang menunggu tidak bisa disetujui.
--     → ajukan_ubah/putuskan_ubah (dan layar) memeriksa Kepada hanya bila berubah (= so_a_kepada_bersih).
--  4. (rendah) pesan tolak Kepada di form SP masih "huruf Kiril/Yunani" untuk tanda hubung ‐ (U+2010) dari PDF. →
--     tanda hubung ‐ ‑ ‒ − masuk daftar izin (seperti – —); layar menyebut karakter yang ditolak.
--  1. (rendah) jejak daftar hitam hanya menyimpan satu teks per kunci — varian nama lain hilang saat segarkan_jejak_hitam()
--     memecah kunci. → setiap teks asal tersimpan sebagai baris sendiri (kunci utama memuat teks).
--  6. (rendah) uji diferensial periksa_view_komisi() tidak menangkap kolom lewat komisi_tier, ambang/pembulatan, atau
--     cabang GM. → komisi_tier/komisi_tier_cash ikut diganti, tiga nilai melintasi batas tier, cabang 'gm' dijalani.
--  5. (rendah) 138 dan 139 belum berpenjaga jalan-ulang. → dipasang (berkas 138/139); berkas ini mencatat versi
--     rantai di rhj_rantai_versi() — 139y menolak dijalankan ulang sendirian sesudah 139z.
--  0. (rendah) uji diri 139y memakai pelanggan daftar hitam ber-id terkecil walau namanya "(tanpa nama)" → diperbaiki di
--     berkas 139y (pelanggan berkunci nama yang sah; tanpa itu uji lewat No. HP).
-- Data yang diubah: hanya pelanggan_hitam_jejak (teks kosong → '' ; kunci utama + teks). Tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

do $$
declare v text;
begin
  if to_regprocedure('public.segarkan_jejak_hitam()') is null
     or not exists (select 1 from pg_attribute where attrelid = 'public.pelanggan_hitam_jejak'::regclass
                     and attname = 'teks' and not attisdropped) then
    raise exception '139z: jalankan 139y dulu.';
  end if;
  if to_regprocedure('public.rhj_rantai_versi()') is not null then
    execute 'select public.rhj_rantai_versi()' into v;
    if v is distinct from '139z' and coalesce(current_setting('rhj.ulang_rantai', true), '') <> 'on' then
      raise exception '139z: berkas ini sudah disusul % — jangan dijalankan ulang sendirian (jalankan ulang seluruh rantai '
                      '138 → % berurutan dalam satu transaksi sesudah set local rhj.ulang_rantai = ''on'').', v, v;
    end if;
  end if;
end $$;

-- ───────────── A · spasi khusus & daftar izin (review 139y no. 2, 4) ─────────────
create or replace function public.teks_tanpa_format(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select normalize(regexp_replace(
    replace(replace(replace(replace(replace(replace(replace(regexp_replace(p,
    '[\u00ad\u034f\u061c\u115f\u1160\u17b4\u17b5\u180b-\u180f\u200b-\u200f\u202a-\u202e\u2060-\u206f\u3164\ufe00-\ufe0f\ufeff\uffa0\u0600-\u0605\u06dd\u070f\u08e2\ufff0-\ufffb\U000110bd\U000110cd\U00013430-\U0001343f\U0001bca0-\U0001bca3\U0001d173-\U0001d17a\U000e0000-\U000e0fff]',
    '', 'g'),
    U&'\FB00', 'ff'), U&'\FB01', 'fi'), U&'\FB02', 'fl'), U&'\FB03', 'ffi'), U&'\FB04', 'ffl'), U&'\FB05', 'st'), U&'\FB06', 'st'),
    '[\u0085\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]', ' ', 'g'),
    NFC)
$$;
comment on function public.teks_tanpa_format(text) is
  '139z: NFC + karakter format (tak terlihat) dibuang + ligatur ﬀ–ﬆ ditulis huruf biasa + spasi khusus (U+2000–200A, '
  'U+202F, U+205F, U+3000, …) ditulis spasi biasa (NFKC hanya di kunci).';

-- daftar izin untuk selain owner/GM/staff (= RE_LATIN_DITERIMA di index.html): spasi biasa, TAB, baris baru, spasi tak
-- terputus, ASCII tercetak, tanda umum (© ® ° ² ³ ¹ ¼ ½ ¾ ‐ ‑ ‒ – — ‘ ’ “ ” … ™ −), huruf Latin beraksen umum.
create or replace function public.ada_huruf_non_latin(p text)
returns boolean language sql immutable parallel safe set search_path = '' as $$
  select regexp_replace(coalesce(public.teks_tanpa_format(p), ''),
           '[\t\n\r\u0020-\u007e\u00a0\u00a9\u00ae\u00b0\u00b2\u00b3\u00b9\u00bc-\u00be\u2010-\u2014\u2018\u2019\u201c\u201d\u2026\u2122\u2212\u00aa\u00ba\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u012f\u0132-\u0137\u0139-\u013e\u0141-\u0148\u014a-\u017e\u01a0\u01a1\u01af\u01b0\u1e00-\u1e95\u1ea0-\u1ef9]',
           '', 'g') <> ''
$$;
comment on function public.ada_huruf_non_latin(text) is
  '139z: true bila ada huruf/simbol di luar daftar izin (huruf Latin biasa & beraksen umum, ASCII, spasi biasa, tanda umum).';
reindex index public.customers_kunci_nama_idx;
reindex index public.customers_kunci_nama_lama_idx;

-- ───────────── B · jejak daftar hitam: satu baris per teks asal (review 139y no. 1) ─────────────
update public.pelanggan_hitam_jejak set teks = '' where teks is null;
alter table public.pelanggan_hitam_jejak alter column teks set default '';
alter table public.pelanggan_hitam_jejak alter column teks set not null;
do $$ begin
  if (select array_agg(a.attname::text order by k.urut)
        from pg_constraint c cross join unnest(c.conkey) with ordinality as k(attnum, urut)
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
       where c.conrelid = 'public.pelanggan_hitam_jejak'::regclass and c.contype = 'p')
     is distinct from array['customer_id','jenis','nilai','teks'] then
    execute 'alter table public.pelanggan_hitam_jejak dr' || 'op constraint pelanggan_hitam_jejak_pkey, '
         || 'add constraint pelanggan_hitam_jejak_pkey primary key (customer_id, jenis, nilai, teks)';
  end if;
end $$;
comment on column public.pelanggan_hitam_jejak.teks is
  '139z: teks asal (nama) jejak berjenis kunci, satu baris per teks ('''' = tidak diketahui / jejak No. HP) — dipakai '
  'segarkan_jejak_hitam() bila definisi kunci berubah.';

create or replace function public.catat_jejak_hitam()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not (coalesce(new.blacklist, false) or (tg_op = 'UPDATE' and coalesce(old.blacklist, false))) then return null; end if;
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
  select new.id, x.jenis, x.nilai, coalesce(x.teks, '')
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

-- dipanggil setiap migrasi yang mengubah kunci_nama_pelanggan / teks_tanpa_format (ATURAN B); tiap teks dihitung sendiri
create or replace function public.segarkan_jejak_hitam()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
  select j.customer_id, 'kunci', k.k, j.teks
    from public.pelanggan_hitam_jejak j
    cross join lateral (select public.kunci_nama_pelanggan(j.teks) as k) k
   where j.jenis = 'kunci' and j.teks <> '' and k.k is distinct from j.nilai
     and char_length(coalesce(k.k, '')) >= 2 and k.k <> 'tanpa nama'
  on conflict do nothing;
  execute 'del' || 'ete from public.pelanggan_hitam_jejak j where j.jenis = ''kunci'' and j.teks <> '''' '
       || 'and j.nilai is distinct from public.kunci_nama_pelanggan(j.teks)';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.segarkan_jejak_hitam() from public, anon, authenticated;
select public.segarkan_jejak_hitam();

-- ───────────── C · Minta ubah SP: Kepada diperiksa hanya bila berubah (review 139y no. 3/8) ─────────────
do $$
declare
  t text[];
  d text; d2 text; n int;
  daftar text[] := array[
    ['public.ajukan_ubah(text,bigint,jsonb,text)', $a$     and public.ada_huruf_non_latin(p_baru->'kepala'->>'kepada') then$a$,
     $b$     and public.ada_huruf_non_latin(p_baru->'kepala'->>'kepada')
     -- 139z (review 139y no. 3): hanya bila Kepada BERUBAH (= so_a_kepada_bersih) — Kepada lama yang ditulis
     -- owner/GM/staff tidak menghalangi usulan qty/harga/alamat
     and btrim(public.teks_tanpa_format(p_baru->'kepala'->>'kepada'))
         is distinct from (select btrim(public.teks_tanpa_format(s.kepada)) from public.sales_orders s where s.id = p_ref) then$b$, '1'],
    ['public.putuskan_ubah(bigint,boolean,text)', $a$    if jsonb_typeof(k) = 'object' and k ? 'kepada' and public.ada_huruf_non_latin(k->>'kepada')
$a$,
     $b$    if jsonb_typeof(k) = 'object' and k ? 'kepada' and public.ada_huruf_non_latin(k->>'kepada')
       -- 139z (review 139y no. 3): hanya bila Kepada BERUBAH dari Kepada SP sekarang
       and btrim(public.teks_tanpa_format(k->>'kepada'))
           is distinct from (select btrim(public.teks_tanpa_format(s.kepada)) from public.sales_orders s where s.id = u.ref_id)
$b$, '1']
  ];
begin
  foreach t slice 1 in array daftar loop
    d := pg_get_functiondef(t[1]::regprocedure);
    if position(t[3] in d) > 0 then continue; end if;   -- sudah ditambal
    n := (length(d) - length(replace(d, t[2], ''))) / length(t[2]);
    if n <> t[4]::int then
      raise exception '139z: % — jangkar "%" muncul % kali (harus %).', t[1], left(t[2], 70), n, t[4];
    end if;
    execute replace(d, t[2], t[3]);
    d2 := pg_get_functiondef(t[1]::regprocedure);
    if replace(d2, t[3], t[2]) <> d then raise exception '139z: % — hasil tambalan tidak sesuai.', t[1]; end if;
  end loop;
end $$;

-- ───────────── D · uji diferensial komisi diperluas (review 139y no. 6) ─────────────
create or replace function public.periksa_view_komisi()
returns void language plpgsql volatile set search_path = public as $$
declare
  v_nama text; v_cacat text;
  v_vonny uuid; v_sales uuid; v_rep bigint; v_so bigint; v_calon bigint[]; v_siap boolean := false; v_galat text;
  a1 bigint; a2 bigint; a3 bigint; a4 bigint;             -- prasyarat (postgres): SP uji muncul di ke-4 view
  n1 bigint; n2 bigint; n3 bigint; n4 bigint; n5 bigint;  -- Vonny
  m1 bigint; m2 bigint; m3 bigint; m4 bigint; m5 bigint;  -- sales
  v_nilai text; v_mode text; v_beda text; v_sidik text[] := '{}'; v_f text; v_g text; v_cek bigint;   -- 139y
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
    -- 139y (review 139v no. 1) + 139z (review 139y no. 6): uji DIFERENSIAL — angka komisi SP uji diganti TIGA kali
    -- (0,0111 · 0,0444 · 0,5: melintasi batas tier 3/4/5 % dan skala) pada tiap cabang sumber komisi; kolom lain yang
    -- terbaca Vonny tidak boleh ikut berubah. Yang diganti: komisi_pct_baris DAN fungsi tier yang bisa dipanggil
    -- langsung dari ekspresi kolom (komisi_tier, komisi_tier_cash), flat pct sales, gm_pct_harga/gm_pct. Cabang 'gm'
    -- (persen baris kosong, harga disetujui GM → pct_berlaku = gm_pct_harga) ikut dijalani.
    foreach v_mode in array array['tier', 'cash', 'flat', 'gm'] loop
      v_sidik := '{}';
      foreach v_nilai in array array['0.0111', '0.0444', '0.5'] loop
        execute format('create or replace function public.komisi_pct_baris(%s) returns numeric language sql as %L',
                       pg_get_function_arguments('public.komisi_pct_baris'::regproc),
                       'select ' || case when v_mode = 'gm' then 'null' else v_nilai end || '::numeric');
        execute format('create or replace function public.komisi_tier(%s) returns numeric language sql as %L',
                       pg_get_function_arguments('public.komisi_tier'::regproc), 'select ' || v_nilai || '::numeric');
        execute format('create or replace function public.komisi_tier_cash(%s) returns numeric language sql as %L',
                       pg_get_function_arguments('public.komisi_tier_cash'::regproc), 'select ' || v_nilai || '::numeric');
        update public.sales_reps set komisi_flat_pct = case when v_mode = 'flat' then v_nilai::numeric end
         where id = (select s.sales_rep_id from public.sales_orders s where s.id = v_so);
        update public.sales_orders set cash_ok = case when v_mode = 'cash' then true end,
               harga_ok = case when v_mode = 'gm' then true else harga_ok end,
               gm_pct_harga = v_nilai::numeric, gm_pct = v_nilai::numeric where id = v_so;
        if v_mode = 'gm' then
          select count(*) into v_cek from public.so_baris_hitung b
           where b.so_id = v_so and b.jenis = 'barang' and b.pct is null and b.pct_berlaku = v_nilai::numeric;
        else
          select count(*) into v_cek from public.so_baris_hitung b
           where b.so_id = v_so and b.jenis = 'barang' and b.pct = v_nilai::numeric;
        end if;
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
      if v_sidik[1] is distinct from v_sidik[2] or v_sidik[1] is distinct from v_sidik[3] then
        v_beda := coalesce(v_beda || ', ', '') || v_mode;
      end if;
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
    raise exception '139z: kolom lain di so_baris_hitung/so_ringkas yang terbaca Vonny ikut berubah saat angka komisi '
                    'berubah (cabang %) — ada kolom yang membawa angka komisi/persen. Tinjau ekspresi kolom view komisi.', v_beda;
  end if;
end $$;
revoke all on function public.periksa_view_komisi() from public, anon, authenticated;
comment on function public.periksa_view_komisi() is
  '139z: struktur + uji perilaku (Vonny/sales) + uji diferensial (tier/cash/flat/gm, 3 nilai); berkas 139k–139y tidak '
  'dijalankan ulang sendirian sesudahnya.';


-- ───────────── E · versi rantai (review 139y no. 5) ─────────────
-- Berkas rantai yang lebih lama menolak dijalankan ulang sendirian sesudah berkas yang menyusulnya (138–139x: sesudah
-- 139y; 139y: sesudah fungsi ini ada). Berkas penyusul berikutnya mengganti nilainya & memasang penjaga di berkas ini.
create or replace function public.rhj_rantai_versi()
returns text language sql immutable set search_path = '' as $$ select '139z'::text $$;
revoke all on function public.rhj_rantai_versi() from public, anon, authenticated;
comment on function public.rhj_rantai_versi() is
  '139z: berkas terakhir rantai 138 → 139z yang terpasang (penjaga jalan-ulang berkas lama).';

-- ───────────── F · uji diri ─────────────
do $$
declare v_tolak text; v_def text; r text; c_id bigint; v_k1 text; v_k2 text; v text;
begin
  -- spasi khusus & daftar izin
  if public.teks_tanpa_format('Toka' || chr(8202) || 'i') <> 'Toka i'
     or public.teks_tanpa_format('A' || chr(8239) || 'B' || chr(12288) || 'C') <> 'A B C'
     or public.ada_huruf_non_latin('PT Jumbo Muara Teh' || chr(8202) || 'nik')      -- jadi spasi biasa (terlihat)
     or not public.ada_huruf_non_latin('PT A' || chr(28) || 'B')                      -- U+001C
     or not public.ada_huruf_non_latin('PT A' || chr(11) || 'B')                      -- tab vertikal
     or public.ada_huruf_non_latin('PT Maju' || chr(8208) || 'Jaya ' || chr(8722) || ' 2')   -- ‐ −
     or public.ada_huruf_non_latin('PT Maju' || chr(160) || 'Jaya' || chr(9) || 'X')  -- spasi tak terputus, TAB
     or not public.ada_huruf_non_latin('PT Maju ' || chr(183) || ' Jaya')             -- · tetap ditolak (dicatat)
     or not public.ada_huruf_non_latin('Rubber ' || chr(8739) || 'ndonesia')          -- ∣
     or public.ada_huruf_non_latin('Café Ünal & Söhne, PT (Jkt) 2 – “X”™')
     or public.kunci_nama_pelanggan('PT Toka' || chr(8202) || 'i Rubber') <> public.kunci_nama_pelanggan('PT Toka i Rubber')
  then
    raise exception '139z: uji spasi/daftar izin gagal.';
  end if;
  -- jejak: dua teks berkunci sama tersimpan sendiri-sendiri; segarkan menghitung tiap teks
  select c.id into c_id from public.customers c order by c.id limit 1;
  v_k1 := public.kunci_nama_pelanggan('Toko Abadi Sentosa 139z');
  v_k2 := public.kunci_nama_pelanggan('Abadi Sentosa 139z');
  begin
    insert into public.pelanggan_hitam_jejak (customer_id, jenis, nilai, teks)
    values (c_id, 'kunci', 'kunci usang 139z', 'Toko Abadi Sentosa 139z'), (c_id, 'kunci', 'kunci usang 139z', 'Abadi Sentosa 139z');
    perform public.segarkan_jejak_hitam();
    r := (select string_agg(j.nilai || '=' || j.teks, '|' order by j.teks) from public.pelanggan_hitam_jejak j
           where j.customer_id = c_id and j.teks like '%139z');
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  if r is distinct from v_k2 || '=Abadi Sentosa 139z|' || v_k1 || '=Toko Abadi Sentosa 139z' then
    raise exception '139z: jejak per teks gagal (%).', r;
  end if;
  if exists (select 1 from public.pelanggan_hitam_jejak j
              where j.jenis = 'kunci' and j.teks <> '' and j.nilai is distinct from public.kunci_nama_pelanggan(j.teks)) then
    raise exception '139z: jejak daftar hitam belum sesuai kunci sekarang.';
  end if;
  -- penjaga view komisi + varian yang dulu lolos (komisi_tier langsung, ambang, cabang gm) kini ditolak
  perform public.periksa_view_komisi();
  v_def := pg_get_viewdef('public.so_baris_hitung'::regclass);
  if position($q$ELSE 'tier'::text$q$ in v_def) = 0 or position($q$THEN 'gm'::text$q$ in v_def) = 0 then
    raise exception '139z: jangkar uji so_baris_hitung tidak ditemukan.';
  end if;
  foreach v in array array[
      $q$ELSE ('tier '::text || (komisi_tier(d.nett_dpp, (l.harga_list)::numeric, (upper(COALESCE(p.brand, ''::text)) = 'HAMMER'::text)))::text)$q$,
      $q$ELSE CASE WHEN (k.pct >= 0.03) THEN 'tier'::text ELSE 'tier '::text END$q$,
      $q$THEN ('gm '::text || (s.gm_pct_harga)::text)$q$] loop
    v_tolak := null;
    begin
      execute 'create or replace view public.so_baris_hitung with (security_invoker = on) as '
              || replace(v_def, case when v like 'THEN%' then $q$THEN 'gm'::text$q$ else $q$ELSE 'tier'::text$q$ end, v);
      perform public.periksa_view_komisi();
      raise exception using errcode = 'P0099';
    exception
      when sqlstate 'P0099' then v_tolak := 'LOLOS';
      when others then v_tolak := sqlerrm;
    end;
    if position('139z: kolom lain' in coalesce(v_tolak, '')) = 0 then
      raise exception '139z: uji diferensial tidak menangkap varian % (hasil: %).', left(v, 60), v_tolak;
    end if;
  end loop;
  if position('139z' in pg_get_functiondef('public.ajukan_ubah(text,bigint,jsonb,text)'::regprocedure)) = 0
     or position('139z' in pg_get_functiondef('public.putuskan_ubah(bigint,boolean,text)'::regprocedure)) = 0 then
    raise exception '139z: tambalan belum terpasang.';
  end if;
end $$;
