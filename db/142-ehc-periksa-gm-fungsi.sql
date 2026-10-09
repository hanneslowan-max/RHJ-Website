-- ═══════════════════════════════════════════════════════════════════════
-- 142 · EHC tahap 3 (2/3) — FUNGSI & RPC pemeriksaan GM per klaim dan
--       daftar bayar finance. Jalankan SESUDAH 141, SEBELUM 143.
--
-- Baru (internal, tidak bisa dipanggil lewat REST):
--   snapshot_klaim_ehc · siapkan_setuju_klaim_ehc (cek lampiran, SP batal,
--   saldo, nominal = Σ alokasi; kunci rekening tujuan saat ini ke
--   ehc_klaim_tujuan) · putuskan_klaim_ehc_inti · ehc_keadaan_bayar
-- Baru (RPC):
--   putuskan_klaim_ehc(p_klaim, p_setuju, p_catatan, p_versi) — GM/owner,
--     per klaim, sesudah cutoff tgl 18, p_versi = diubah_pada||dibuat_pada
--     (40001 bila basi), tolak wajib alasan; lintas boleh di sini.
--   setujui_klaim_ehc_massal(p_daftar) — 1–100 butir {klaim, versi};
--     lintas dilewati, hasil per klaim (tidak all-or-nothing).
--   rekap_ehc_bulanan(p_bulan) — "Kunci daftar bayar EHC": hanya periode
--     periode_bayar_ehc(hari ini WIB), sekali per periode.
--   keluarkan_klaim_ehc_batch(p_klaim, p_alasan) — transfer gagal, sebelum
--     referensi bank diisi.
--   ehc_daftar_bayar(p_bulan, p_batch) — rekening hanya owner/GM/finance.
-- Diganti (dibangun dari definisi DEV hidup, nama & argumen tetap):
--   ehc_klaim_siap_transfer (status 'disetujui', rekening terkunci, lintas
--   tidak lagi dikecualikan) · putuskan_klaim_cepat · minta_klaim_cepat ·
--   batalkan_klaim_ehc · rekap_ehc_cepat (tanpa membuang baris, WIB) ·
--   ajukan_transfer (HANYA blok 'ehc' diganti penolakan 0A000 lewat
--   pengganti teks di definisi hidup; cabang komisi tidak disentuh).
-- Tidak disentuh: simpan_klaim_ehc, putuskan_transfer, rekap_transfer,
--   tarik_pengajuan_transfer, isi_referensi_batch, batalkan_klaim_cepat,
--   laporan_komisi, ehc_saldo_sp, kas_sales.
--
-- Keputusan Hannes 9 Okt 2026: P1 GM/owner boleh memutus klaim yang ia
-- buat/ubah/minta cepat (tidak ada cek "pemutus terlibat" — tercatat di
-- gm_oleh & ehc_klaim_putusan); P2 tolak cepat = hanya cepatnya ditolak,
-- klaim tetap diajukan; P3 ditolak sesudah komisi diklaim → saldo ke kas
-- sales (otomatis lewat ehc_saldo_sp); P4 hak baca dipersempit di 141.
-- Galat: 42501 hak · 22023 keadaan · P0002 tidak ada · 40001 versi basi /
-- daftar berubah · 23514 saldo · 0A000 jalur pensiun. Urutan kunci: klaim
-- (id naik) → SP (id naik), sama dengan simpan_klaim_ehc.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1. snapshot isi klaim (untuk jejak putusan) ──────────────────────────
create or replace function public.snapshot_klaim_ehc(p_klaim bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'versi', coalesce(k.diubah_pada, k.dibuat_pada),
    'nominal', (select n.nominal from public.ehc_klaim_nilai n where n.klaim_id = k.id),
    'alokasi', (select coalesce(jsonb_agg(jsonb_build_object(
                  'so_id', a.so_id, 'no_sp', s.no_sp, 'nominal', a.nominal, 'lunas', s.lunas, 'batal', s.batal,
                  'total_ehc', trunc(coalesce(r.total_ehc, 0), 2),
                  'terpakai', (select coalesce(sum(x.nominal), 0) from public.ehc_klaim_alokasi x
                                 join public.ehc_klaim kx on kx.id = x.klaim_id
                                where x.so_id = a.so_id and kx.status in ('diajukan','disetujui')),
                  'tertutup', exists (select 1 from public.komisi_klaim kk where kk.so_id = a.so_id))
                  order by a.so_id), '[]'::jsonb)
                  from public.ehc_klaim_alokasi a
                  join public.sales_orders s on s.id = a.so_id
                  left join public.so_ringkas r on r.so_id = a.so_id
                 where a.klaim_id = k.id and a.nominal > 0),
    'lintas', public.klaim_ehc_lintas(k.id),
    'customer_id', k.customer_id, 'keperluan', k.keperluan, 'cara_bayar', k.cara_bayar,
    'berkas', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'path', f.path) order by f.id), '[]'::jsonb)
                 from public.ehc_klaim_berkas f where f.klaim_id = k.id and f.dibuang_pada is null),
    'cepat_alasan', k.cepat_alasan)
  from public.ehc_klaim k where k.id = p_klaim
$$;

-- ── 2. siapkan persetujuan (pemanggil sudah mengunci klaim FOR UPDATE) ───
-- Tujuan dibaca SAAT INI lalu dikunci ke ehc_klaim_tujuan: transfer → PIC
-- aktif milik customer penerima, rekening terisi, bukan rekening sales mana
-- pun; reimburse → rekening sales pemilik klaim (diisi finance); tunai →
-- tanpa rekening; kartu kredit → tahap 2.
create or replace function public.siapkan_setuju_klaim_ehc(p_klaim bigint, p_jalur text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare k public.ehc_klaim; a record; v_sum numeric := 0; v_nom numeric;
        v_pic public.customer_pics; v_rek public.sales_rep_rekening;
        v_sumber text; v_bank text; v_norek text; v_an text;
begin
  select * into k from public.ehc_klaim where id = p_klaim;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if not exists (select 1 from public.ehc_klaim_berkas f where f.klaim_id = p_klaim and f.dibuang_pada is null) then
    raise exception 'Klaim tanpa lampiran tidak bisa disetujui — tolak dengan alasan.' using errcode = '22023';
  end if;
  perform 1 from public.sales_orders s
   where s.id in (select x.so_id from public.ehc_klaim_alokasi x where x.klaim_id = p_klaim and x.nominal > 0)
   order by s.id for update;
  for a in
    select x.so_id, x.nominal, s.no_sp, s.batal, trunc(coalesce(r.total_ehc, 0), 2) as total_ehc,
           (select coalesce(sum(y.nominal), 0) from public.ehc_klaim_alokasi y
              join public.ehc_klaim ky on ky.id = y.klaim_id
             where y.so_id = x.so_id and ky.status in ('diajukan','disetujui')) as terpakai
      from public.ehc_klaim_alokasi x
      join public.sales_orders s on s.id = x.so_id
      left join public.so_ringkas r on r.so_id = x.so_id
     where x.klaim_id = p_klaim and x.nominal > 0
     order by x.so_id
  loop
    if a.batal then
      raise exception 'SP % sudah dibatalkan — klaim ini tidak bisa disetujui. Tolak dengan alasan.', a.no_sp
        using errcode = '22023';
    end if;
    if a.total_ehc < a.terpakai then
      raise exception 'Saldo EHC SP % tidak cukup: EHC SP % sedangkan klaim aktif atas SP itu %.',
        a.no_sp, public.rp_teks(a.total_ehc), public.rp_teks(a.terpakai) using errcode = '23514';
    end if;
    v_sum := v_sum + a.nominal;
  end loop;
  select n.nominal into v_nom from public.ehc_klaim_nilai n where n.klaim_id = p_klaim;
  if v_sum = 0 or v_nom is distinct from v_sum then
    raise exception 'Nominal klaim EHC #% (%) tidak sama dengan jumlah alokasi SP-nya (%).',
      p_klaim, coalesce(public.rp_teks(v_nom), '-'), public.rp_teks(v_sum) using errcode = '23514';
  end if;

  if k.cara_bayar = 'transfer' then
    select * into v_pic from public.customer_pics where id = k.pic_id;
    if v_pic.id is null or not coalesce(v_pic.aktif, true) then
      raise exception 'PIC penerima transfer klaim ini sudah tidak aktif atau tidak ada — tolak dengan alasan.'
        using errcode = '22023';
    end if;
    if v_pic.customer_id is distinct from k.customer_id then
      raise exception 'PIC % bukan PIC customer penerima klaim ini.', v_pic.nama using errcode = '22023';
    end if;
    if coalesce(btrim(v_pic.bank), '') = '' or coalesce(btrim(v_pic.no_rekening), '') = '' then
      raise exception 'PIC % belum punya rekening.', v_pic.nama using errcode = '22023';
    end if;
    if exists (select 1 from public.sales_rep_rekening r
                where regexp_replace(r.no_rekening, '\D', '', 'g') = regexp_replace(v_pic.no_rekening, '\D', '', 'g')) then
      raise exception 'Rekening PIC % sama dengan rekening sales. Transfer ke customer harus ke rekening customer.',
        v_pic.nama using errcode = '42501';
    end if;
    v_sumber := 'pic'; v_bank := v_pic.bank; v_norek := v_pic.no_rekening; v_an := v_pic.atas_nama;
  elsif k.cara_bayar = 'reimburse' then
    select * into v_rek from public.sales_rep_rekening where sales_rep_id = k.sales_rep_id;
    if not found then
      raise exception 'Rekening sales belum diisi finance — klaim reimburse ini belum bisa disetujui.'
        using errcode = '22023';
    end if;
    v_sumber := 'sales'; v_bank := v_rek.bank; v_norek := v_rek.no_rekening; v_an := v_rek.atas_nama;
  elsif k.cara_bayar = 'tunai' then
    v_sumber := 'tunai';
  else
    raise exception 'Cara bayar % belum bisa diputus GM (kartu kredit perusahaan menyusul di tahap 2).', k.cara_bayar
      using errcode = '0A000';
  end if;

  insert into public.ehc_klaim_tujuan (klaim_id, sumber, pic_id, bank, no_rekening, atas_nama, dikunci_oleh)
  values (p_klaim, v_sumber, case when v_sumber = 'pic' then v_pic.id end, v_bank, v_norek, v_an, auth.uid());
  return public.snapshot_klaim_ehc(p_klaim)
      || jsonb_build_object('jalur', p_jalur,
                            'tujuan', jsonb_build_object('sumber', v_sumber, 'pic_id', case when v_sumber = 'pic' then v_pic.id end));
end $$;

-- ── 3. inti putusan GM per klaim (P1: tanpa larangan memutus sendiri) ────
create or replace function public.putuskan_klaim_ehc_inti(p_klaim bigint, p_setuju boolean, p_catatan text,
                                                          p_versi timestamptz, p_massal boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare k public.ehc_klaim; v_cat text := nullif(btrim(coalesce(p_catatan, '')), ''); v_snap jsonb;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutus klaim EHC.' using errcode = '42501';
  end if;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC #% berstatus % — sudah diputus.', p_klaim, k.status using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim EHC #% sudah masuk batch transfer #%.', p_klaim, k.transfer_batch_id using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is distinct from false then
    raise exception 'Klaim EHC #% sedang meminta pencairan cepat — putuskan di antrean EHC cepat.', p_klaim
      using errcode = '22023';
  end if;
  if public.hari_ini_wib() <= public.cutoff_ehc(k.periode) then
    raise exception 'Klaim EHC periode % diperiksa GM sesudah tgl 18 (cutoff %). Kalau mendesak, sales meminta EHC cepat.',
      k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
  end if;
  if p_versi is null or p_versi <> coalesce(k.diubah_pada, k.dibuat_pada) then
    raise exception 'Klaim EHC #% berubah sejak dimuat — muat ulang lalu periksa lagi.', p_klaim using errcode = '40001';
  end if;
  if p_setuju is null then
    raise exception 'Pilih setujui atau tolak.' using errcode = '22023';
  end if;
  if not p_setuju and v_cat is null then
    raise exception 'Penolakan klaim EHC wajib beralasan — sales perlu tahu kenapa.' using errcode = '22023';
  end if;
  if p_massal and public.klaim_ehc_lintas(p_klaim) then
    raise exception 'Klaim EHC #% lintas customer — putuskan satu per satu.', p_klaim using errcode = '22023';
  end if;

  if p_setuju then
    v_snap := public.siapkan_setuju_klaim_ehc(p_klaim, 'periksa');
  else
    v_snap := public.snapshot_klaim_ehc(p_klaim);
  end if;
  update public.ehc_klaim
     set status = case when p_setuju then 'disetujui' else 'ditolak' end,
         gm_oleh = auth.uid(), gm_pada = now(), gm_catatan = v_cat, gm_jalur = 'periksa'
   where id = p_klaim;
  insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh)
  values (p_klaim, 'periksa', case when p_setuju then 'setuju' else 'tolak' end, v_cat, v_snap, auth.uid());
  return jsonb_build_object('klaim', p_klaim, 'setuju', p_setuju,
                            'nominal', v_snap->'nominal', 'alokasi', v_snap->'alokasi');
end $$;

-- ── 4. RPC putusan per klaim ─────────────────────────────────────────────
create or replace function public.putuskan_klaim_ehc(p_klaim bigint, p_setuju boolean, p_catatan text default null,
                                                     p_versi timestamptz default null)
returns text language plpgsql security definer set search_path = public as $$
declare v jsonb; v_belum text; v_sp text; v_kas text;
begin
  v := public.putuskan_klaim_ehc_inti(p_klaim, p_setuju, p_catatan, p_versi, false);
  select string_agg(e->>'no_sp', ', ' order by (e->>'so_id')::bigint) filter (where not (e->>'lunas')::boolean),
         string_agg(e->>'no_sp', ', ' order by (e->>'so_id')::bigint),
         string_agg(e->>'no_sp', ', ' order by (e->>'so_id')::bigint) filter (where (e->>'tertutup')::boolean)
    into v_belum, v_sp, v_kas
    from jsonb_array_elements(v->'alokasi') e;
  if p_setuju then
    return 'DISETUJUI. Klaim EHC #' || p_klaim || ' (' || coalesce(public.rp_teks((v->>'nominal')::numeric), '-')
        || ') dibayar finance mulai tgl 20 begitu semua SP lunas' || coalesce('; SP ' || v_belum || ' belum lunas', '') || '.';
  end if;
  return 'DITOLAK. Saldo ' || coalesce(public.rp_teks((v->>'nominal')::numeric), '-') || ' kembali ke SP ' || coalesce(v_sp, '-')
      || coalesce('; SP ' || v_kas || ' sudah tertutup komisi — saldonya masuk kas sales', '') || '.';
end $$;

-- ── 5. RPC persetujuan massal (hasil per klaim) ──────────────────────────
create or replace function public.setujui_klaim_ehc_massal(p_daftar jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v jsonb; v_ok jsonb := '[]'::jsonb; v_lewat jsonb := '[]'::jsonb; v_gagal jsonb := '[]'::jsonb;
        v_total numeric := 0; v_n integer; v_d integer; v_kosong integer;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh menyetujui klaim EHC.' using errcode = '42501';
  end if;
  if p_daftar is null or jsonb_typeof(p_daftar) <> 'array' or jsonb_array_length(p_daftar) not between 1 and 100 then
    raise exception 'Daftar klaim harus berisi 1 sampai 100 butir {klaim, versi}.' using errcode = '22023';
  end if;
  begin
    select count(*), count(distinct x.klaim), count(*) filter (where x.klaim is null)
      into v_n, v_d, v_kosong
      from jsonb_to_recordset(p_daftar) as x(klaim bigint, versi timestamptz);
  exception when others then
    raise exception 'Daftar klaim tidak terbaca — tiap butir {klaim, versi}.' using errcode = '22023';
  end;
  if v_kosong > 0 or v_d <> v_n then
    raise exception 'Daftar klaim berisi butir tanpa nomor klaim atau klaim yang sama dua kali.' using errcode = '22023';
  end if;
  for r in select x.klaim, x.versi from jsonb_to_recordset(p_daftar) as x(klaim bigint, versi timestamptz)
            order by x.klaim loop
    if public.klaim_ehc_lintas(r.klaim) then
      v_lewat := v_lewat || jsonb_build_object('klaim', r.klaim, 'alasan', 'lintas customer — putuskan satu per satu');
      continue;
    end if;
    begin
      v := public.putuskan_klaim_ehc_inti(r.klaim, true, null, r.versi, true);
      v_ok := v_ok || jsonb_build_object('klaim', r.klaim, 'nominal', v->'nominal');
      v_total := v_total + coalesce((v->>'nominal')::numeric, 0);
    exception when others then
      v_gagal := v_gagal || jsonb_build_object('klaim', r.klaim, 'kode', sqlstate, 'pesan', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('disetujui', v_ok, 'dilewati', v_lewat, 'gagal', v_gagal, 'total', v_total);
end $$;

-- ── 6. klaim siap dibayar periode p_bulan (internal) ─────────────────────
create or replace function public.ehc_klaim_siap_transfer(p_bulan text)
returns setof bigint language sql stable security definer set search_path = public as $function$
  select k.id from public.ehc_klaim k
   where k.status = 'disetujui'
     and k.transfer_batch_id is null
     and k.periode <= p_bulan
     and k.cara_bayar in ('transfer','reimburse','tunai')
     and exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id)
     and not (k.cepat_minta and k.cepat_ok is distinct from false)
     and public.klaim_ehc_terkunci_pengajuan(k.id) is null
     and exists (select 1 from public.ehc_klaim_alokasi a where a.klaim_id = k.id and a.nominal > 0)
     and exists (select 1 from public.ehc_klaim_berkas f where f.klaim_id = k.id and f.dibuang_pada is null)
     and not exists (select 1 from public.ehc_klaim_alokasi a
                       join public.sales_orders s on s.id = a.so_id
                      where a.klaim_id = k.id and a.nominal > 0 and (not s.lunas or s.batal))
$function$;

-- Keadaan bayar satu klaim untuk daftar finance periode p_bulan.
create or replace function public.ehc_keadaan_bayar(k public.ehc_klaim, p_bulan text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when k.transfer_batch_id is not null then case when k.ditransfer_pada is null then 'dibatch' else 'ditransfer' end
    when k.status = 'diajukan' then
      case when k.periode <= p_bulan and public.hari_ini_wib() > public.cutoff_ehc(k.periode)
                and not (k.cepat_minta and k.cepat_ok is null) then 'menunggu_gm' end
    when k.status <> 'disetujui' then null
    when k.cepat_minta and k.cepat_ok then 'cepat'
    when k.periode > p_bulan then null
    when not exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id) then 'tanpa_rekening'
    when exists (select 1 from public.ehc_klaim_alokasi a join public.sales_orders s on s.id = a.so_id
                  where a.klaim_id = k.id and a.nominal > 0 and (not s.lunas or s.batal)) then 'menunggu_lunas'
    when k.id in (select public.ehc_klaim_siap_transfer(p_bulan)) then 'siap'
    else 'tertahan' end
$$;

-- ── 7. RPC kunci daftar bayar bulanan ────────────────────────────────────
-- Gerbang keras: hanya periode_bayar_ehc(hari ini WIB) — terlambat boleh,
-- periode lama yang tertunda ikut otomatis; sekali per periode.
create or replace function public.rekap_ehc_bulanan(p_bulan text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_hari date := public.hari_ini_wib(); v_ids bigint[]; v_n integer; v_total numeric(14,2) := 0;
        v_batch bigint; v_ada bigint; v_upd integer; v_ml integer; v_mg integer; v_tr integer;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengunci daftar bayar EHC.' using errcode = '42501';
  end if;
  if p_bulan is null or p_bulan !~ '^\d{4}-\d{2}$' then
    raise exception 'Periode harus dalam bentuk YYYY-MM.' using errcode = '22023';
  end if;
  if p_bulan <> public.periode_bayar_ehc(v_hari) then
    raise exception 'Yang bisa dikunci hari ini periode % (periode berikutnya mulai tgl 20). Periode lama yang tertunda ikut otomatis.',
      public.periode_bayar_ehc(v_hari) using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('rhj.rekap_ehc'));
  select b.id into v_ada from public.transfer_batch b
   where b.jenis = 'ehc' and b.periode_bayar = p_bulan and not b.cepat and b.jumlah_klaim > 0
   order by b.id limit 1;
  if v_ada is not null then
    raise exception 'Daftar bayar EHC periode % sudah dikunci (batch #%).', p_bulan, v_ada using errcode = '22023';
  end if;

  perform 1 from public.ehc_klaim k
   where k.id in (select public.ehc_klaim_siap_transfer(p_bulan)) order by k.id for update;
  perform 1 from public.sales_orders s
   where s.id in (select a.so_id from public.ehc_klaim_alokasi a
                   where a.nominal > 0 and a.klaim_id in (select public.ehc_klaim_siap_transfer(p_bulan)))
   order by s.id for share;
  select array_agg(x order by x) into v_ids from public.ehc_klaim_siap_transfer(p_bulan) x;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n > 0 then
    select coalesce(sum(n.nominal), 0) into v_total from public.ehc_klaim_nilai n where n.klaim_id = any(v_ids);
    insert into public.transfer_batch (jenis, bulan, periode_bayar, tanggal, jumlah_klaim, total, cepat, dibuat_oleh)
    values ('ehc', p_bulan, p_bulan, v_hari, v_n, v_total, false, auth.uid())
    returning id into v_batch;
    perform set_config('rhj.batch', 'on', true);
    update public.ehc_klaim set transfer_batch_id = v_batch
     where id = any(v_ids) and transfer_batch_id is null and status = 'disetujui';
    get diagnostics v_upd = row_count;
    perform set_config('rhj.batch', 'off', true);
    if v_upd <> v_n then
      raise exception 'Daftar klaim EHC berubah saat dikunci (% dari %) — ulangi.', v_upd, v_n using errcode = '40001';
    end if;
  end if;

  select count(*) filter (where s.x = 'menunggu_lunas'), count(*) filter (where s.x = 'menunggu_gm'),
         count(*) filter (where s.x = 'tanpa_rekening')
    into v_ml, v_mg, v_tr
    from (select public.ehc_keadaan_bayar(k, p_bulan) as x from public.ehc_klaim k
           where k.transfer_batch_id is null and k.status in ('diajukan','disetujui')) s;
  return jsonb_build_object('batch', v_batch, 'jumlah', v_n, 'total', v_total,
    'menunggu_lunas', v_ml, 'menunggu_gm', v_mg, 'tanpa_rekening', v_tr,
    'pesan', case when v_n = 0
      then 'Tidak ada klaim EHC yang siap dibayar untuk periode ' || p_bulan || '. Tidak ada batch yang dibuat.'
      else v_n || ' klaim EHC (' || public.rp_teks(v_total) || ') dikunci di batch #' || v_batch
           || '. Transfer sesuai daftar; yang gagal keluarkan; lalu isi referensi.' end);
end $$;

-- ── 8. RPC keluarkan klaim dari batch (transfer gagal) ───────────────────
-- Klaim tetap 'disetujui': bulanan ikut tgl 20 berikutnya, cepat kembali ke
-- EHC emergency. Urutan kunci batch → klaim (sama dengan isi referensi).
create or replace function public.keluarkan_klaim_ehc_batch(p_klaim bigint, p_alasan text)
returns text language plpgsql security definer set search_path = public as $$
declare k public.ehc_klaim; b public.transfer_batch; v_batch bigint; v_nom numeric(14,2);
        v_alasan text := nullif(btrim(coalesce(p_alasan, '')), '');
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh mengeluarkan klaim dari batch.' using errcode = '42501';
  end if;
  if v_alasan is null then
    raise exception 'Alasan wajib diisi (mis. transfer gagal, rekening tidak aktif).' using errcode = '22023';
  end if;
  select transfer_batch_id into v_batch from public.ehc_klaim where id = p_klaim;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if v_batch is null then
    raise exception 'Klaim EHC #% tidak sedang di batch transfer.', p_klaim using errcode = '22023';
  end if;
  select * into b from public.transfer_batch where id = v_batch for update;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if k.transfer_batch_id is distinct from b.id then
    raise exception 'Klaim EHC #% berubah — muat ulang.', p_klaim using errcode = '40001';
  end if;
  if b.jenis <> 'ehc' then
    raise exception 'Batch #% bukan batch EHC.', b.id using errcode = '22023';
  end if;
  if b.no_referensi is not null then
    raise exception 'Batch #% sudah berreferensi — uang dianggap keluar; klaim tidak bisa dikeluarkan.', b.id
      using errcode = '22023';
  end if;
  select n.nominal into v_nom from public.ehc_klaim_nilai n where n.klaim_id = p_klaim;
  perform set_config('rhj.batch', 'on', true);
  update public.ehc_klaim set transfer_batch_id = null where id = p_klaim;
  update public.transfer_batch set jumlah_klaim = jumlah_klaim - 1, total = total - coalesce(v_nom, 0) where id = b.id;
  perform set_config('rhj.batch', 'off', true);
  insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh)
  values (p_klaim, 'bayar', 'keluar_batch', v_alasan,
          jsonb_build_object('batch', b.id, 'cepat', b.cepat, 'nominal', v_nom), auth.uid());
  return 'Klaim EHC #' || p_klaim || ' dikeluarkan dari batch #' || b.id || '. '
      || case when b.cepat then 'Klaim kembali ke daftar EHC emergency.'
              else 'Klaim tetap disetujui dan ikut daftar bayar tgl 20 berikutnya.' end;
end $$;

-- ── 9. RPC daftar bayar EHC (Laporan Finance) ────────────────────────────
-- Tanpa p_batch: siap / menunggu_lunas / tanpa_rekening / menunggu_gm /
-- cepat. Dengan p_batch: isi batch itu. Rekening hanya owner/GM/finance;
-- Lenni & staff melihat baris tanpa rekening; peran lain 42501.
create or replace function public.ehc_daftar_bayar(p_bulan text, p_batch bigint default null)
returns table(klaim_id bigint, keadaan text, periode text, sales_rep_id bigint, sales text, customer text,
              lintas boolean, keperluan text, cara_bayar text, sumber_tujuan text, bank text, no_rekening text,
              atas_nama text, nominal numeric, sp jsonb, gm_nama text, gm_pada timestamptz, batch_id bigint,
              ditransfer_pada timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_rek boolean := public.boleh_rekap_transfer();
begin
  if not public.boleh_lihat_nilai_klaim() then
    raise exception 'Anda tidak berhak melihat daftar bayar EHC.' using errcode = '42501';
  end if;
  if p_batch is null and (p_bulan is null or p_bulan !~ '^\d{4}-\d{2}$') then
    raise exception 'Periode harus dalam bentuk YYYY-MM.' using errcode = '22023';
  end if;
  return query
  select k.id, x.keadaan, k.periode, k.sales_rep_id, r.nama, c.nama, public.klaim_ehc_lintas(k.id),
         k.keperluan, k.cara_bayar, t.sumber,
         case when v_rek then t.bank end, case when v_rek then t.no_rekening end, case when v_rek then t.atas_nama end,
         n.nominal::numeric,
         (select coalesce(jsonb_agg(jsonb_build_object('so_id', a.so_id, 'no_sp', s.no_sp, 'nominal', a.nominal,
                                                       'lunas', s.lunas, 'batal', s.batal) order by a.so_id), '[]'::jsonb)
            from public.ehc_klaim_alokasi a join public.sales_orders s on s.id = a.so_id
           where a.klaim_id = k.id and a.nominal > 0),
         g.nama, k.gm_pada, k.transfer_batch_id, k.ditransfer_pada
    from public.ehc_klaim k
    cross join lateral (select public.ehc_keadaan_bayar(k, coalesce(p_bulan, k.periode)) as keadaan) x
    left join public.sales_reps r on r.id = k.sales_rep_id
    left join public.customers c on c.id = k.customer_id
    left join public.ehc_klaim_tujuan t on t.klaim_id = k.id
    left join public.ehc_klaim_nilai n on n.klaim_id = k.id
    left join public.profiles g on g.id = k.gm_oleh
   where (p_batch is null and x.keadaan in ('siap','menunggu_lunas','tanpa_rekening','menunggu_gm','cepat'))
      or (p_batch is not null and k.transfer_batch_id = p_batch)
   order by x.keadaan, r.nama, k.id;
end $$;

-- ── 10. EHC cepat: putusan GM (signature tetap) ──────────────────────────
-- Setuju = putusan GM per klaim jalur cepat (status 'disetujui', rekening
-- dikunci), TANPA syarat lunas, lintas boleh. Tolak (P2) = hanya cepatnya
-- ditolak; klaim tetap diajukan dan diperiksa GM sesudah tgl 18.
create or replace function public.putuskan_klaim_cepat(p_klaim bigint, p_setuju boolean, p_catatan text default null::text)
returns text language plpgsql security definer set search_path = public as $function$
declare k public.ehc_klaim; v_cat text; v_sp text; v_pj bigint; v_snap jsonb;
begin
  if not public.boleh_approve() then
    raise exception 'Hanya GM atau owner yang boleh memutuskan pencairan cepat.' using errcode = '42501';
  end if;
  v_cat := nullif(btrim(coalesce(p_catatan, '')), '');
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then
    raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002';
  end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC #% berstatus % — tidak bisa diputus lagi.', p_klaim, k.status using errcode = '22023';
  end if;
  if not k.cepat_minta or k.cepat_ok is not null then
    raise exception 'Klaim #% tidak sedang menunggu putusan pencairan cepat.', p_klaim using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim #% sudah ditransfer lewat batch #%.', p_klaim, k.transfer_batch_id using errcode = '22023';
  end if;
  if p_setuju is null then
    raise exception 'Pilih setujui atau tolak.' using errcode = '22023';
  end if;
  if not p_setuju and v_cat is null then
    raise exception 'Penolakan wajib beralasan — sales-nya harus bisa menjelaskan ke '
                    'pelanggannya kenapa tidak bisa dipercepat.' using errcode = '22023';
  end if;
  if p_setuju then
    v_pj := public.klaim_ehc_terkunci_pengajuan(p_klaim);
    if v_pj is not null then
      raise exception 'Klaim #% masih terkunci di pengajuan transfer bulanan #%. Tarik dulu pengajuan itu.',
        p_klaim, v_pj using errcode = '22023';
    end if;
    v_snap := public.siapkan_setuju_klaim_ehc(p_klaim, 'cepat');
  end if;

  perform set_config('rhj.cepat', 'on', true);
  if p_setuju then
    update public.ehc_klaim
       set cepat_ok = true, cepat_catatan = v_cat, cepat_diputus_oleh = auth.uid(), cepat_diputus_pada = now(),
           cepat_minta = true, status = 'disetujui',
           gm_oleh = auth.uid(), gm_pada = now(), gm_catatan = v_cat, gm_jalur = 'cepat'
     where id = p_klaim;
  else
    update public.ehc_klaim
       set cepat_ok = false, cepat_catatan = v_cat, cepat_diputus_oleh = auth.uid(), cepat_diputus_pada = now(),
           cepat_minta = true
     where id = p_klaim;
  end if;
  perform set_config('rhj.cepat', 'off', true);

  insert into public.ehc_cepat_log (klaim_id, aksi, alasan, oleh)
  values (p_klaim, case when p_setuju then 'setuju' else 'tolak' end, v_cat, auth.uid());
  if p_setuju then
    insert into public.ehc_klaim_putusan (klaim_id, jalur, aksi, catatan, snapshot, oleh)
    values (p_klaim, 'cepat', 'setuju', v_cat, v_snap, auth.uid());
  end if;

  select no_sp into v_sp from public.sales_orders where id = k.so_id;
  return case when p_setuju
    then 'Klaim EHC ' || coalesce(v_sp, '#' || p_klaim) || ' DISETUJUI untuk dicairkan cepat. '
       || 'Finance melihatnya lewat tombol "EHC emergency" di Laporan Finance.'
    else 'Permintaan klaim cepat untuk ' || coalesce(v_sp, '#' || p_klaim) || ' DITOLAK. '
       || 'Klaimnya tetap diajukan dan diperiksa GM sesudah tgl 18 seperti biasa.'
  end;
end $function$;

-- ── 11. EHC cepat: permintaan (dari definisi DEV) ────────────────────────
-- Berubah: klaim lintas kini boleh (GM memutus per klaim); reimburse
-- diperiksa ke rekening sales (bukan salinan di kepala klaim); pesan khusus
-- untuk klaim yang sudah disetujui.
create or replace function public.minta_klaim_cepat(p_klaim bigint, p_alasan text)
returns text language plpgsql security definer set search_path = public as $function$
declare k public.ehc_klaim; v_alasan text; v_pj bigint; v_sp text;
begin
  v_alasan := nullif(btrim(coalesce(p_alasan, '')), '');

  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then
    raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002';
  end if;
  if not public.boleh_minta_klaim_cepat(p_klaim) then
    raise exception 'Anda tidak berhak mengajukan pencairan cepat untuk klaim ini.'
      using errcode = '42501';
  end if;
  if k.status = 'disetujui' then
    raise exception 'Klaim EHC ini sudah DISETUJUI GM — yang ditunggu sekarang daftar bayar finance, '
                    'tidak perlu dipercepat.' using errcode = '22023';
  end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC ini berstatus % — hanya klaim yang masih diajukan yang bisa dipercepat.',
                    k.status using errcode = '22023';
  end if;
  if not exists (select 1 from public.ehc_klaim_berkas f where f.klaim_id = p_klaim and f.dibuang_pada is null) then
    raise exception 'Klaim ini belum punya lampiran. Ubah klaimnya dan lampirkan bukti dulu.' using errcode = '22023';
  end if;
  if k.cara_bayar = 'transfer' and coalesce(btrim(k.no_rekening), '') = '' then
    raise exception 'Klaim ini belum punya rekening tujuan.' using errcode = '22023';
  end if;
  if k.cara_bayar = 'reimburse'
     and not exists (select 1 from public.sales_rep_rekening r where r.sales_rep_id = k.sales_rep_id) then
    raise exception 'Klaim ini belum punya rekening tujuan (rekening sales belum diisi finance).' using errcode = '22023';
  end if;

  if v_alasan is null then
    raise exception 'Alasan mendesak wajib diisi — GM tidak bisa memutuskan pencairan di '
                    'luar jadwal tanpa tahu apa yang mendesak.' using errcode = '22023';
  end if;
  if length(v_alasan) < 10 then
    raise exception 'Alasan mendesak terlalu pendek (% huruf). Tulis apa yang mendesak dan '
                    'kapan uangnya dibutuhkan — GM memutuskan dari kalimat ini.',
                    length(v_alasan) using errcode = '22023';
  end if;

  if k.transfer_batch_id is not null then
    raise exception 'Klaim ini sudah ditransfer lewat batch #% — tidak ada yang perlu '
                    'dipercepat lagi.', k.transfer_batch_id using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is null then
    raise exception 'Klaim ini sudah diajukan sebagai klaim cepat dan masih menunggu GM. '
                    'Tarik dulu kalau alasannya mau diperbaiki.' using errcode = '22023';
  end if;

  v_pj := public.klaim_ehc_terkunci_pengajuan(p_klaim);
  if v_pj is not null then
    raise exception
      'Klaim ini sudah terkunci di pengajuan transfer bulanan #% yang belum selesai. '
      'Finance menarik dulu pengajuan itu (tarik_pengajuan_transfer), baru klaim ini '
      'diajukan sebagai klaim cepat.', v_pj
      using errcode = '22023';
  end if;

  perform set_config('rhj.cepat', 'on', true);
  update public.ehc_klaim
     set cepat_minta = true, cepat_ok = null, cepat_alasan = v_alasan, cepat_catatan = null,
         cepat_diminta_oleh = auth.uid(), cepat_diminta_pada = now(),
         cepat_diputus_oleh = null, cepat_diputus_pada = null
   where id = p_klaim;
  perform set_config('rhj.cepat', 'off', true);

  insert into public.ehc_cepat_log (klaim_id, aksi, alasan, oleh)
  values (p_klaim, 'minta', v_alasan, auth.uid());

  select no_sp into v_sp from public.sales_orders where id = k.so_id;
  return 'Klaim EHC ' || coalesce(v_sp, '#' || p_klaim) || ' diajukan sebagai EHC CEPAT dan '
      || 'masuk antrean GM. Selama menunggu, klaim ini tidak ikut pemeriksaan bulanan GM.';
end $function$;

-- ── 12. batalkan klaim (dari definisi DEV) ───────────────────────────────
-- Berubah: hanya EHC cepat yang MASIH MENUNGGU GM yang menahan (cepat yang
-- sudah disetujui tapi belum dibayar bisa dibatalkan GM/owner, ATURAN L71);
-- klaim di batch → keluarkan dulu dari batch.
create or replace function public.batalkan_klaim_ehc(p_klaim bigint, p_alasan text)
returns text language plpgsql security definer set search_path = public as $function$
declare k public.ehc_klaim; v_alasan text := nullif(btrim(coalesce(p_alasan, '')), '');
        v_lewat boolean;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak membatalkan klaim EHC.' using errcode = '42501';
  end if;
  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
  if not (public.klaim_ehc_saya(p_klaim) or public.peran_saya() in ('owner','gm','staff')) then
    raise exception 'Klaim EHC ini bukan milik Anda.' using errcode = '42501';
  end if;
  if k.status not in ('diajukan','disetujui') then
    raise exception 'Klaim EHC ini berstatus %, tidak bisa dibatalkan.', k.status using errcode = '22023';
  end if;
  if k.transfer_batch_id is not null then
    raise exception 'Klaim EHC ini ada di batch transfer #% — %.', k.transfer_batch_id,
      case when k.ditransfer_pada is null then 'keluarkan dulu dari batch (finance) bila transfernya gagal'
           else 'uangnya sudah keluar' end using errcode = '22023';
  end if;
  if public.klaim_ehc_terkunci_pengajuan(p_klaim) is not null then
    raise exception 'Klaim EHC ini sudah masuk pengajuan transfer. Tarik dulu pengajuannya.' using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is null then
    raise exception 'Klaim ini sedang diajukan sebagai EHC cepat dan menunggu GM. Tarik permintaan cepatnya dulu.'
      using errcode = '22023';
  end if;
  v_lewat := public.hari_ini_wib() > public.cutoff_ehc(k.periode);
  if (v_lewat or k.status = 'disetujui') and not public.boleh_approve() then
    raise exception 'Periode % sudah lewat cutoff (%) atau klaim sudah disetujui. Pembatalan sekarang hanya oleh GM/owner.',
                    k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
  end if;
  if v_alasan is null then
    raise exception 'Alasan pembatalan wajib diisi.' using errcode = '22023';
  end if;
  update public.ehc_klaim
     set status = 'batal', batal_alasan = v_alasan, batal_oleh = auth.uid(), batal_pada = now()
   where id = p_klaim;
  insert into public.ehc_klaim_log (klaim_id, aksi, catatan, oleh)
  values (p_klaim, 'batal',
          v_alasan || case when k.status = 'disetujui' then ' (dibatalkan GM/owner sesudah disetujui)'
                           when v_lewat then ' (dibatalkan GM/owner sesudah cutoff)' else '' end, auth.uid());
  return 'Klaim EHC dibatalkan. Saldo EHC SP-nya kembali dan bisa dipakai lagi.';
end $function$;

-- ── 13. EHC emergency: batch cepat (tanpa membuang baris) ────────────────
-- Hitung dulu, baru buat batch; tanggal & bulan WIB; lunas tidak disyaratkan;
-- klaim dengan SP batal atau tanpa rekening terkunci dilewati.
create or replace function public.rekap_ehc_cepat()
returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_hari date := public.hari_ini_wib(); v_ids bigint[]; v_n integer; v_total numeric(14,2) := 0;
        v_batch bigint; v_lewat integer; v_upd integer;
begin
  if not public.boleh_rekap_transfer() then
    raise exception 'Hanya owner, GM, atau finance yang boleh menandai pencairan cepat.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('rhj.rekap_ehc'));
  perform 1 from public.ehc_klaim k
   where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null
   order by k.id for update;
  perform 1 from public.sales_orders s
   where s.id in (select a.so_id from public.ehc_klaim_alokasi a join public.ehc_klaim k on k.id = a.klaim_id
                   where a.nominal > 0 and k.status = 'disetujui' and k.cepat_minta and k.cepat_ok
                     and k.transfer_batch_id is null)
   order by s.id for share;
  select array_agg(k.id order by k.id) into v_ids from public.ehc_klaim k
   where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null
     and exists (select 1 from public.ehc_klaim_tujuan t where t.klaim_id = k.id)
     and public.klaim_ehc_terkunci_pengajuan(k.id) is null
     and not exists (select 1 from public.ehc_klaim_alokasi a join public.sales_orders s on s.id = a.so_id
                      where a.klaim_id = k.id and a.nominal > 0 and s.batal);
  v_n := coalesce(array_length(v_ids, 1), 0);
  select count(*) into v_lewat from public.ehc_klaim k
   where k.status = 'disetujui' and k.cepat_minta and k.cepat_ok and k.transfer_batch_id is null
     and k.id <> all(coalesce(v_ids, '{}'::bigint[]));
  if v_n = 0 then
    return jsonb_build_object('batch', null, 'jumlah', 0, 'total', 0, 'dilewati', v_lewat,
      'pesan', case when v_lewat > 0
        then 'Tidak ada klaim cepat yang bisa ditandai: ' || v_lewat || ' klaim yang sudah disetujui GM '
          || 'belum punya rekening tujuan terkunci atau SP-nya batal.'
        else 'Belum ada klaim EHC yang disetujui GM untuk dicairkan cepat. Tidak ada batch '
          || 'baru yang dibuat.' end);
  end if;
  select coalesce(sum(n.nominal), 0) into v_total from public.ehc_klaim_nilai n where n.klaim_id = any(v_ids);
  insert into public.transfer_batch (jenis, bulan, tanggal, jumlah_klaim, total, cepat, dibuat_oleh)
  values ('ehc', to_char(v_hari, 'YYYY-MM'), v_hari, v_n, v_total, true, auth.uid())
  returning id into v_batch;
  perform set_config('rhj.batch', 'on', true);
  update public.ehc_klaim set transfer_batch_id = v_batch
   where id = any(v_ids) and transfer_batch_id is null and status = 'disetujui';
  get diagnostics v_upd = row_count;
  perform set_config('rhj.batch', 'off', true);
  if v_upd <> v_n then
    raise exception 'Daftar klaim EHC cepat berubah saat dikunci (% dari %) — ulangi.', v_upd, v_n using errcode = '40001';
  end if;
  return jsonb_build_object('batch', v_batch, 'jumlah', v_n, 'total', v_total, 'dilewati', v_lewat,
    'pesan', v_n || ' klaim EHC cepat masuk batch #' || v_batch || ' (total ' || public.rp_teks(v_total)
          || '). Transfer sesuai daftar; yang gagal keluarkan; lalu isi nomor referensinya.'
          || case when v_lewat > 0
               then ' ' || v_lewat || ' klaim lain dilewati (tanpa rekening terkunci atau SP batal).'
               else '' end);
end $function$;

-- ── 14. ajukan_transfer: hanya blok 'ehc' yang diganti ───────────────────
-- Dibangun dari definisi DEV hidup (dipakai bersama alur komisi tgl 25):
-- blok "if p_jenis = 'ehc' and … cutoff … end if;" diganti penolakan 0A000;
-- seluruh teks lain (cabang komisi) tetap byte-identik. Pola harus cocok
-- tepat satu kali.
do $$
declare
  v_def  text;
  v_pola text := $p$if p_jenis = 'ehc' and public.hari_ini_wib() <= public.cutoff_ehc(p_bulan) then$p$;
  v_baru text := $b$if p_jenis = 'ehc' then
    raise exception 'Pembayaran EHC tidak lagi lewat pengajuan transfer (berkas 142): GM memeriksa per klaim sesudah tgl 18, finance mengunci daftar bayar mulai tgl 20 (rekap_ehc_bulanan).'
      using errcode = '0A000';
  end if;$b$;
  v_a integer; v_e integer; v_n integer;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ajukan_transfer' and p.prokind = 'f';
  if v_def is null then raise exception '142: ajukan_transfer tidak ada di DB.'; end if;
  if strpos(v_def, '(berkas 142)') > 0 then
    raise notice '142: ajukan_transfer sudah memuat blok 142.';
    return;
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_pola, ''))) / length(v_pola);
  if v_n <> 1 then
    raise exception '142: blok EHC ajukan_transfer ditemukan % kali (harus 1) — definisi DEV berubah, periksa manual.', v_n;
  end if;
  v_a := strpos(v_def, v_pola);
  v_e := strpos(substr(v_def, v_a), 'end if;');
  if v_e = 0 then raise exception '142: akhir blok EHC ajukan_transfer tidak ditemukan.'; end if;
  execute left(v_def, v_a - 1) || v_baru || substr(v_def, v_a + v_e - 1 + length('end if;'));
end $$;

-- ── 15. hak eksekusi ─────────────────────────────────────────────────────
revoke all on function public.snapshot_klaim_ehc(bigint)                    from public, anon, authenticated;
revoke all on function public.siapkan_setuju_klaim_ehc(bigint, text)        from public, anon, authenticated;
revoke all on function public.putuskan_klaim_ehc_inti(bigint, boolean, text, timestamptz, boolean)
  from public, anon, authenticated;
revoke all on function public.ehc_klaim_siap_transfer(text)                 from public, anon, authenticated;
revoke all on function public.ehc_keadaan_bayar(public.ehc_klaim, text)     from public, anon, authenticated;

revoke all on function public.putuskan_klaim_ehc(bigint, boolean, text, timestamptz) from public, anon;
revoke all on function public.setujui_klaim_ehc_massal(jsonb)               from public, anon;
revoke all on function public.rekap_ehc_bulanan(text)                       from public, anon;
revoke all on function public.keluarkan_klaim_ehc_batch(bigint, text)       from public, anon;
revoke all on function public.ehc_daftar_bayar(text, bigint)                from public, anon;
revoke all on function public.putuskan_klaim_cepat(bigint, boolean, text)   from public, anon;
revoke all on function public.minta_klaim_cepat(bigint, text)               from public, anon;
revoke all on function public.batalkan_klaim_ehc(bigint, text)              from public, anon;
revoke all on function public.rekap_ehc_cepat()                             from public, anon;
revoke all on function public.ajukan_transfer(text, text, text)             from public, anon;
grant execute on function public.putuskan_klaim_ehc(bigint, boolean, text, timestamptz) to authenticated;
grant execute on function public.setujui_klaim_ehc_massal(jsonb)            to authenticated;
grant execute on function public.rekap_ehc_bulanan(text)                    to authenticated;
grant execute on function public.keluarkan_klaim_ehc_batch(bigint, text)    to authenticated;
grant execute on function public.ehc_daftar_bayar(text, bigint)             to authenticated;
grant execute on function public.putuskan_klaim_cepat(bigint, boolean, text) to authenticated;
grant execute on function public.minta_klaim_cepat(bigint, text)            to authenticated;
grant execute on function public.batalkan_klaim_ehc(bigint, text)           to authenticated;
grant execute on function public.rekap_ehc_cepat()                          to authenticated;
grant execute on function public.ajukan_transfer(text, text, text)          to authenticated;
