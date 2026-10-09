-- ═══════════════════════════════════════════════════════════════════════
-- 139k · Temuan keamanan #1 (keputusan Hannes 9 Okt, no. 5a, 6, 7): angka komisi, klaim komisi, rekening & lampirannya
--        hanya untuk peran yang memang melihatnya
-- (nomor 139k: jatah nomor sesi ini 120–139; "k" = komisi. Diurutkan sesudah 139/139b dan SEBELUM berkas EHC 140+.
--  Objek komisi milik sesi EHC — dikerjakan dengan sepengetahuan sesi EHC, keputusan no. 7.)
--
-- Celah (uji DEV, rollback; desain + kritik "desain-keamanan-akhir"): view security_invoker so_ringkas, so_baris_hitung,
-- komisi_belum_klaim, cash_belum_cocok barisnya mengikuti RLS SP (so_baca: semua SP untuk owner/GM/staff/finance/Lie
-- Sian/Ichi/Vonny/Lenni) tanpa penjaga kolom → Vonny membaca so_ringkas.komisi 54 SP (Rp 19,7 jt), pct per baris,
-- komisi_belum_klaim, /rpc/komisi_berlaku (penjaga boleh_lihat_sp, bukan penjaga nominal); Lie Sian & Ichi juga.
-- komisi_klaim (persen GM, rekening sales), komisi_klaim_berkas & berkas di storage terbaca semua peran boleh_lihat_semua_jual
-- (padanan EHC sudah memakai boleh_lihat_nilai_klaim). Rekening sales di klaim komisi juga terbaca staff & Lenni.
--
-- Perbaikan — yang boleh melihat angka komisi = boleh_lihat_nilai_klaim() (owner, GM, staff, finance, Lenni; semua SP)
-- + sales untuk SP atas namanya sendiri (sama dengan laporan_komisi, ehc_saldo_sp, layar "Komisi Anda"):
--  A (5a) so_baris_hitung.pct & pct_berlaku, so_ringkas.komisi → NULL (bukan 0) bagi peran lain; cash_belum_cocok tanpa
--     baris bagi peran lain. Penyaring hanya berlaku bila current_user = authenticated/anon (REST/GraphQL): fungsi
--     SECURITY DEFINER (komisi_hitung, gerbang GM/EHC, status_sp_hitung, laporan_*) tetap membaca angka utuh, siapa pun
--     pemicunya. Kolom lain (grand total, status, ada_bawah_list, perlu_gm, …) tidak berubah.
--  B (5a) komisi_berlaku memakai boleh_lihat_komisi_sp (internal); komisi_belum_klaim tanpa baris bagi peran lain;
--     baca komisi_klaim, komisi_klaim_berkas, dan berkas komisi/* di storage = boleh_lihat_nilai_klaim() atau sales
--     pemilik klaim (disamakan dengan EHC).
--  C (6) rekening sales di klaim komisi hanya owner, GM, finance, dan sales pemilik klaim (sama dengan rekening master
--     sales_rep_rekening): kolom bank/no_rekening/atas_nama komisi_klaim tidak lagi bisa di-SELECT lewat REST; salinannya
--     di tabel komisi_klaim_rekening (diisi trigger dari komisi_klaim, RLS sendiri) — layar meng-embed tabel itu.
--     Fungsi definer (ajukan_klaim_komisi, rekap_transfer, …) tetap memakai kolom aslinya.
--  D Penjaga agar penyaring A/B tidak hilang diam-diam: event trigger jaga_view_komisi menolak CREATE/ALTER VIEW atas
--     so_ringkas, so_baris_hitung, cash_belum_cocok, komisi_belum_klaim yang tidak lagi memuat boleh_lihat_nilai_klaim
--     atau tidak security_invoker. Fungsi periksa_view_komisi() untuk dipanggil di akhir migrasi yang menyentuh view itu.
-- Yang TIDAK ditutup (diterima, ATURAN B): komisi tetap bisa DIPERKIRAKAN dari harga baris SP, price list, aturan tier,
-- dan persen GM / flat / harga khusus yang terbuka bagi peran yang melihat harga SP (uji kritik: Vonny 54/54 SP persis).
-- so_baris_hitung.sumber_pct (jenis sumber, bukan angka) tidak ditutup.
-- Rumus komisi, gerbang, pembekuan berkas 130 tidak berubah. Tidak ada data yang diubah (selain salinan rekening);
-- tidak ada objek yang dibuang. Jangkar bergantung pada bentuk pg_get_viewdef PostgreSQL 17 — gagal keras bila beda.
-- ═══════════════════════════════════════════════════════════════════════

-- 0. pemeriksa internal (TANPA cabang current_user — dipakai fungsi definer)
create or replace function public.boleh_lihat_komisi_sp(p_so bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sales_orders s
                  where s.id = p_so
                    and (public.boleh_lihat_nilai_klaim()
                         or (public.peran_saya() = 'sales' and s.sales_rep_id = public.sales_rep_saya())))
$$;
revoke all on function public.boleh_lihat_komisi_sp(bigint) from public, anon, authenticated;

-- A + B2: tambal definisi view yang SEDANG HIDUP (gagal keras bila jangkar tidak muncul tepat sekali)
do $$
declare v_boleh text; v_def text; a text; a_pb text; a_kom text; a_cb text; a_kb text;
begin
  v_boleh := '((CURRENT_USER <> ALL (ARRAY[''authenticated''::name, ''anon''::name]))'
          || ' OR ( SELECT boleh_lihat_nilai_klaim() AS boleh_lihat_nilai_klaim)'
          || ' OR ((( SELECT peran_saya() AS peran_saya) = ''sales''::text)'
          || ' AND (s.sales_rep_id = ( SELECT sales_rep_saya() AS sales_rep_saya))))';
  a_pb  := E'CASE\n            WHEN (l.jenis = ''biaya''::text) THEN NULL::numeric\n            WHEN (k.pct IS NOT NULL) THEN k.pct';
  a_kom := 'COALESCE(sum((b.nilai_barang_dpp * b.pct_berlaku)) FILTER (WHERE (b.pct_berlaku IS NOT NULL)), (0)::numeric) AS komisi';
  a_cb  := 'WHERE (s.cash_minta AND';
  a_kb  := 'WHERE ((NOT s.batal) AND (NOT (EXISTS';

  -- (A1) so_baris_hitung: kolom pct & pct_berlaku (k.pct internal untuk sumber_pct/perlu_gm tidak diubah)
  v_def := pg_get_viewdef('public.so_baris_hitung'::regclass);
  if position('boleh_lihat_nilai_klaim' in v_def) = 0 then
    foreach a in array array['k.pct,', a_pb, ' OFFSET 0) k'] loop
      if (length(v_def) - length(replace(v_def, a, ''))) / length(a) <> 1 then
        raise exception '139k: so_baris_hitung — jangkar "%" tidak muncul tepat sekali; periksa definisinya dulu.', a;
      end if;
    end loop;
    v_def := replace(v_def, 'k.pct,', 'CASE WHEN kv.boleh THEN k.pct ELSE NULL::numeric END AS pct,');
    v_def := replace(v_def, a_pb,
      E'CASE\n            WHEN (NOT kv.boleh) THEN NULL::numeric\n            WHEN (l.jenis = ''biaya''::text) THEN NULL::numeric\n            WHEN (k.pct IS NOT NULL) THEN k.pct');
    v_def := replace(v_def, ' OFFSET 0) k',
      E' OFFSET 0) k\n     CROSS JOIN LATERAL ( SELECT ' || v_boleh || ' AS boleh) kv');
    execute 'create or replace view public.so_baris_hitung with (security_invoker = on) as ' || v_def;
  end if;

  -- (A2) so_ringkas.komisi → NULL bagi peran tertutup
  v_def := pg_get_viewdef('public.so_ringkas'::regclass);
  if position('boleh_lihat_nilai_klaim' in v_def) = 0 then
    if (length(v_def) - length(replace(v_def, a_kom, ''))) / length(a_kom) <> 1 then
      raise exception '139k: so_ringkas — rumus komisi tidak ditemukan tepat sekali; periksa definisinya dulu.';
    end if;
    v_def := replace(v_def, a_kom, 'CASE WHEN ' || v_boleh || ' THEN ' || replace(a_kom, ' AS komisi', '')
                                  || ' ELSE NULL::numeric END AS komisi');
    execute 'create or replace view public.so_ringkas with (security_invoker = on) as ' || v_def;
  end if;

  -- (A3) cash_belum_cocok (tidak dipakai layar): barisnya hanya bagi yang boleh melihat komisi
  v_def := pg_get_viewdef('public.cash_belum_cocok'::regclass);
  if position('boleh_lihat_nilai_klaim' in v_def) = 0 then
    if (length(v_def) - length(replace(v_def, a_cb, ''))) / length(a_cb) <> 1 then
      raise exception '139k: cash_belum_cocok — jangkar WHERE tidak ditemukan tepat sekali.';
    end if;
    execute 'create or replace view public.cash_belum_cocok with (security_invoker = on) as '
         || replace(v_def, a_cb, 'WHERE (' || v_boleh || ' AND s.cash_minta AND');
  end if;

  -- (B2) komisi_belum_klaim: barisnya (termasuk gm_pct, harga_ok, komisi) hanya bagi yang boleh — sama dengan ehc_saldo_sp
  v_def := pg_get_viewdef('public.komisi_belum_klaim'::regclass);
  if position('boleh_lihat_nilai_klaim' in v_def) = 0 then
    if (length(v_def) - length(replace(v_def, a_kb, ''))) / length(a_kb) <> 1 then
      raise exception '139k: komisi_belum_klaim — jangkar WHERE tidak ditemukan tepat sekali.';
    end if;
    execute 'create or replace view public.komisi_belum_klaim with (security_invoker = on) as '
         || replace(v_def, a_kb, 'WHERE (' || v_boleh || ' AND (NOT s.batal) AND (NOT (EXISTS');
  end if;
end $$;

-- (B1) /rpc/komisi_berlaku: penjaga nominal (rumus tidak berubah)
create or replace function public.komisi_berlaku(p_so bigint)
returns numeric language sql stable security definer set search_path = public as $$
  select public.komisi_hitung(p_so) where public.boleh_lihat_komisi_sp(p_so)
$$;

-- (B3) klaim komisi, lampirannya, dan berkasnya di storage — disamakan dengan EHC
alter policy komk_baca on public.komisi_klaim using (
  public.boleh_lihat_nilai_klaim()
  or (public.peran_saya() = 'sales' and public.sales_rep_saya() is not null
      and (sales_rep_id = public.sales_rep_saya()
           or exists (select 1 from public.sales_orders s
                       where s.id = komisi_klaim.so_id and s.sales_rep_id = public.sales_rep_saya()))));
alter policy kkb_baca on public.komisi_klaim_berkas
  using (public.boleh_lihat_nilai_klaim() or public.klaim_komisi_saya(klaim_id));
alter policy rhj_komisi_bukti_baca on storage.objects using (
  bucket_id = 'dokumen' and name like 'komisi/%'
  and exists (select 1 from public.komisi_klaim_berkas f
               where f.path = objects.name
                 and (public.boleh_lihat_nilai_klaim() or public.klaim_komisi_saya(f.klaim_id))));

-- (C) rekening sales di klaim komisi: owner, GM, finance, sales pemilik klaim
do $$ begin   -- klaim dihapus (owner) → salinannya ikut (ON DEL-ETE CASCADE; ditulis lewat execute — lihat catatan MCP)
  execute 'create table if not exists public.komisi_klaim_rekening ('
       || ' klaim_id bigint primary key references public.komisi_klaim(id) on ' || 'DEL' || 'ETE cascade,'
       || ' sales_rep_id bigint, bank text, no_rekening text, atas_nama text)';
end $$;
comment on table public.komisi_klaim_rekening is
  '139k (keputusan 6): salinan rekening sales di klaim komisi untuk dibaca layar — diisi trigger dari komisi_klaim.';
alter table public.komisi_klaim_rekening enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'komisi_klaim_rekening'
                    and policyname = 'kkr_baca') then
    create policy kkr_baca on public.komisi_klaim_rekening for select using (
      public.peran_saya() in ('owner','gm','finance')
      or (public.peran_saya() = 'sales' and public.sales_rep_saya() is not null
          and sales_rep_id = public.sales_rep_saya()));
  end if;
end $$;
revoke all on public.komisi_klaim_rekening from public, anon, authenticated;
grant select on public.komisi_klaim_rekening to authenticated;

create or replace function public.salin_rekening_klaim_komisi()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.komisi_klaim_rekening (klaim_id, sales_rep_id, bank, no_rekening, atas_nama)
  values (new.id, new.sales_rep_id, new.bank, new.no_rekening, new.atas_nama)
  on conflict (klaim_id) do update
    set sales_rep_id = excluded.sales_rep_id, bank = excluded.bank,
        no_rekening = excluded.no_rekening, atas_nama = excluded.atas_nama;
  return null;
end $$;
revoke all on function public.salin_rekening_klaim_komisi() from public, anon, authenticated;
create or replace trigger komisi_klaim_zz_rekening
  after insert or update of sales_rep_id, bank, no_rekening, atas_nama on public.komisi_klaim
  for each row execute function public.salin_rekening_klaim_komisi();

insert into public.komisi_klaim_rekening (klaim_id, sales_rep_id, bank, no_rekening, atas_nama)
select k.id, k.sales_rep_id, k.bank, k.no_rekening, k.atas_nama from public.komisi_klaim k
on conflict (klaim_id) do update
  set sales_rep_id = excluded.sales_rep_id, bank = excluded.bank,
      no_rekening = excluded.no_rekening, atas_nama = excluded.atas_nama;

-- kolom rekening komisi_klaim tidak bisa di-SELECT lewat REST (hak per kolom; fungsi definer tidak terpengaruh)
revoke select on public.komisi_klaim from public, anon, authenticated;
grant select (id, so_id, sales_rep_id, telat, pct_gm, tanggal, dibuat_pada, dibuat_oleh, transfer_batch_id)
  on public.komisi_klaim to authenticated;

-- (D) penjaga penyaring view komisi
create or replace function public.periksa_view_komisi()
returns void language plpgsql stable set search_path = public as $$
declare r record;
begin
  for r in select c.oid, c.relname, c.reloptions from pg_class c
            where c.relnamespace = 'public'::regnamespace
              and c.relname in ('so_ringkas','so_baris_hitung','cash_belum_cocok','komisi_belum_klaim') loop
    if position('boleh_lihat_nilai_klaim' in pg_get_viewdef(r.oid)) = 0
       or not coalesce('security_invoker=on' = any (r.reloptions), false) then
      raise exception '139k: view % kehilangan penyaring komisi / security_invoker — sertakan lagi predikat berkas 139k '
                      '(lihat ATURAN B › Akses & peran).', r.relname;
    end if;
  end loop;
end $$;
revoke all on function public.periksa_view_komisi() from public, anon, authenticated;

create or replace function public.jaga_view_komisi_tertutup()
returns event_trigger language plpgsql set search_path = public as $f$
declare r record; v_opsi text[];
begin
  for r in select * from pg_event_trigger_ddl_commands()
            where object_type = 'view'
              and object_identity in ('public.so_ringkas','public.so_baris_hitung','public.cash_belum_cocok',
                                      'public.komisi_belum_klaim') loop
    select c.reloptions into v_opsi from pg_class c where c.oid = r.objid;
    if position('boleh_lihat_nilai_klaim' in pg_get_viewdef(r.objid)) = 0
       or not coalesce('security_invoker=on' = any (v_opsi), false) then
      raise exception '139k: view % kehilangan penyaring komisi / security_invoker — sertakan lagi predikat berkas 139k '
                      '(lihat ATURAN B › Akses & peran).', r.object_identity;
    end if;
  end loop;
end $f$;
revoke all on function public.jaga_view_komisi_tertutup() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi') then
    create event trigger jaga_view_komisi on ddl_command_end
      when tag in ('CREATE VIEW', 'ALTER VIEW')
      execute function public.jaga_view_komisi_tertutup();
  end if;
end $$;

do $$ begin
  perform public.periksa_view_komisi();
  if has_function_privilege('authenticated', 'public.boleh_lihat_komisi_sp(bigint)', 'execute')
     or has_column_privilege('authenticated', 'public.komisi_klaim', 'no_rekening', 'select')
     or not has_column_privilege('authenticated', 'public.komisi_klaim', 'pct_gm', 'select')
     or not has_table_privilege('authenticated', 'public.komisi_klaim_rekening', 'select') then
    raise exception '139k: hak komisi belum sesuai';
  end if;
  if (select count(*) from public.komisi_klaim) <> (select count(*) from public.komisi_klaim_rekening) then
    raise exception '139k: salinan rekening klaim komisi tidak lengkap';
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'jaga_view_komisi' and evtenabled = 'O') then
    raise exception '139k: event trigger jaga_view_komisi tidak aktif';
  end if;
end $$;
