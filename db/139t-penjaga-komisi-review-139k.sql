-- ═══════════════════════════════════════════════════════════════════════
-- 139t · Tindak lanjut review berkas 139k (temuan keamanan #1: angka komisi hanya untuk peran yang berhak)
-- (nomor 139t: jatah nomor sesi ini 120–139; "t" = review 139k; sesudah 139s, sebelum berkas EHC 140+.)
--
-- Temuan review yang dikonfirmasi di DEV & perbaikannya:
--  3. (rendah) so_baris_hitung.pct_berlaku tetap menampilkan persen bila pemeriksaan hak bernilai NULL (mis. akun sales
--     yang tautan sales-nya dikosongkan): `WHEN (NOT kv.boleh)` dengan NULL tidak tertangkap. → `WHEN (kv.boleh IS NOT
--     TRUE)` (tambal definisi hidup; isi lain sama).
--  2/5. (rendah) Penjaga jaga_view_komisi bisa dilewati DDL: ALTER TABLE … SET/RESET (security_invoker) atas view itu,
--     CREATE RULE "_RETURN", rename, atau menyebut kata boleh_lihat_nilai_klaim hanya di teks. → fungsi penjaga baru:
--     relasi dicari dari objid (rule → pg_rewrite.ev_class), nama dicek sesudah perintah (rename tercakup), predikat
--     dibuktikan lewat ketergantungan pg_depend view → fungsi boleh_lihat_nilai_klaim() (kata di teks tidak dihitung),
--     event trigger kedua jaga_view_komisi_b untuk tag ALTER TABLE & CREATE RULE. periksa_view_komisi() kini juga uji
--     perilaku (Vonny: angka komisi kosong; sales: hanya SP-nya, baris tidak melebar) — dipanggil di akhir migrasi.
--  4. (rendah) penjaga menolak view sah yang ditulis `security_invoker = true` / tanpa nilai. → dibaca lewat
--     pg_options_to_table(...)::boolean (on/true/yes/1 diterima; off/false ditolak).
--  Tidak di berkas ini: 1 (rekening sales tersalin di klaim EHC reimburse — objek sesi EHC; pertanyaan Q29 untuk Hannes).
-- Tidak ada data yang diubah; tidak ada objek yang dibuang.
-- ═══════════════════════════════════════════════════════════════════════

-- A · (no. 3) pct_berlaku: NULL dianggap tidak berhak
do $$
declare v text; a text := 'WHEN (NOT kv.boleh) THEN NULL::numeric'; b text := 'WHEN (kv.boleh IS NOT TRUE) THEN NULL::numeric'; n int;
begin
  v := pg_get_viewdef('public.so_baris_hitung'::regclass);
  if position(b in v) = 0 then
    n := (length(v) - length(replace(v, a, ''))) / length(a);
    if n <> 1 then raise exception '139t: so_baris_hitung — jangkar pct_berlaku muncul % kali (harus 1).', n; end if;
    execute 'create or replace view public.so_baris_hitung with (security_invoker = on) as ' || replace(v, a, b);
  end if;
end $$;

-- B · penjaga: apakah view komisi masih sah (security_invoker & bergantung pada boleh_lihat_nilai_klaim())
create or replace function public.view_komisi_cacat(p_rel oid)
returns text language plpgsql stable set search_path = public as $$
declare c record; v_inv boolean;
begin
  select k.relkind, k.reloptions into c from pg_class k where k.oid = p_rel;
  if c.relkind is null then return 'tidak ada'; end if;
  if c.relkind <> 'v' then return 'bukan view'; end if;
  select o.option_value::boolean into v_inv from pg_options_to_table(c.reloptions) o where o.option_name = 'security_invoker';
  if not coalesce(v_inv, false) then return 'tidak security_invoker'; end if;
  if not exists (select 1 from pg_rewrite rw
                   join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = rw.oid
                  where rw.ev_class = p_rel and d.refclassid = 'pg_proc'::regclass
                    and d.refobjid = 'public.boleh_lihat_nilai_klaim()'::regprocedure) then
    return 'tanpa pemanggilan boleh_lihat_nilai_klaim()';
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
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi_b') then
    create event trigger jaga_view_komisi_b on ddl_command_end
      when tag in ('ALTER TABLE', 'CREATE RULE')
      execute function public.jaga_view_komisi_tertutup();
  end if;
end $$;

-- C · periksa_view_komisi(): struktur + uji perilaku (dipanggil di akhir setiap migrasi yang menyentuh view komisi)
create or replace function public.periksa_view_komisi()
returns void language plpgsql volatile set search_path = public as $$
declare
  v_nama text; v_cacat text; v_klaim text := current_setting('request.jwt.claims', true);
  v_vonny uuid; v_sales uuid; v_rep bigint; n1 bigint; n2 bigint; n3 bigint; n4 bigint;
begin
  foreach v_nama in array array['so_ringkas','so_baris_hitung','cash_belum_cocok','komisi_belum_klaim'] loop
    v_cacat := public.view_komisi_cacat(coalesce(to_regclass('public.' || v_nama)::oid, 0));
    if v_cacat is not null then
      raise exception '139k/139t: view public.% kehilangan penyaring komisi (%) — sertakan lagi predikat berkas 139k dan '
                      'security_invoker (lihat ATURAN B › Akses & peran).', v_nama, v_cacat;
    end if;
  end loop;
  -- uji perilaku (139t): penyaring benar-benar bekerja, bukan hanya tertulis
  select p.id into v_vonny from public.profiles p where p.peran = 'vonny' order by p.id limit 1;
  select p.id, sr.id into v_sales, v_rep from public.profiles p join public.sales_reps sr on sr.profile_id = p.id
   where p.peran = 'sales' order by p.id limit 1;
  begin
    if v_vonny is not null then
      perform set_config('request.jwt.claims', json_build_object('sub', v_vonny, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select count(komisi) into n1 from public.so_ringkas;
      select count(pct) + count(pct_berlaku) into n2 from public.so_baris_hitung;
      select count(*) into n3 from public.komisi_belum_klaim;
      select count(*) into n4 from public.cash_belum_cocok;
      reset role;
      if n1 + n2 + n3 + n4 <> 0 then
        raise exception '139t: Vonny masih melihat angka komisi (so_ringkas %, so_baris_hitung %, komisi_belum_klaim %, '
                        'cash_belum_cocok %).', n1, n2, n3, n4;
      end if;
    end if;
    if v_sales is not null then
      perform set_config('request.jwt.claims', json_build_object('sub', v_sales, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select count(*) into n1 from public.so_ringkas r where r.komisi is not null and r.sales_rep_id is distinct from v_rep;
      select count(*) into n2 from public.so_baris_hitung b join public.sales_orders s on s.id = b.so_id
       where (b.pct is not null or b.pct_berlaku is not null) and s.sales_rep_id is distinct from v_rep;
      select count(*) into n3 from public.komisi_belum_klaim k where k.sales_rep_id is distinct from v_rep;
      select (select count(*) from public.so_ringkas) - (select count(*) from public.sales_orders) into n4;
      reset role;
      if n1 + n2 + n3 <> 0 or n4 > 0 then
        raise exception '139t: sales (rep %) melihat komisi/baris SP sales lain (so_ringkas %, so_baris_hitung %, '
                        'komisi_belum_klaim %, kelebihan baris so_ringkas %).', v_rep, n1, n2, n3, n4;
      end if;
    end if;
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', coalesce(v_klaim, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_klaim, ''), true);
end $$;
revoke all on function public.periksa_view_komisi() from public, anon, authenticated;

-- D · uji diri
do $$
begin
  perform public.periksa_view_komisi();
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi' and evtenabled in ('O','A'))
     or not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi_b' and evtenabled in ('O','A')) then
    raise exception '139t: event trigger jaga_view_komisi / jaga_view_komisi_b tidak aktif.';
  end if;
  if position('kv.boleh IS NOT TRUE' in pg_get_viewdef('public.so_baris_hitung'::regclass)) = 0 then
    raise exception '139t: pct_berlaku belum ditambal.';
  end if;
end $$;
