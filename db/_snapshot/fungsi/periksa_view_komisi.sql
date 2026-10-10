CREATE OR REPLACE FUNCTION public.periksa_view_komisi()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
end $function$;
