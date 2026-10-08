-- ═══════════════════════════════════════════════════════════════════════
-- 126 · #57 tampilan SET di Surat Pesanan (data tetap per pcs)
--
-- Keputusan Hannes (7 Okt): SP dari PO yang berisi set (mis. "Set OSU 3" (2 rem + 2 mati)" × 3) selama ini
-- hanya tampil sebagai baris pcs per roda — set-nya tidak terbaca lagi di SP, laci Vonny, dan kirim partial.
-- Datanya TETAP per pcs (komisi, price list, gerbang GM, EHC, kirim, invoice tidak berubah sama sekali);
-- yang ditambah hanya PENANDA pengelompokan supaya layar bisa menampilkan "3 set · Set OSU 3" …":
--   set_grup  nomor kelompok set di dalam satu SP (1, 2, …)
--   set_nama  nama set (deskripsi baris PO / nama set master)
--   set_qty   jumlah set (bilangan bulat)
--   set_isi   isi per set untuk produk baris ini (mis. 2 roda rem per set)
-- Kelompok "utuh" bila untuk tiap produk di kelompok itu Σ qty = set_qty × set_isi; selain itu layar menulis
-- "set (sudah diubah)" (keputusan a). Qty baris set dikunci di form SP dari PO (keputusan b) — di layar saja;
-- Minta ubah tetap bisa mengubahnya (GM yang memutuskan) dan tandanya ikut terbawa.
--
-- (1) kolom + CHECK sol_set_lengkap: keempatnya kosong, atau set_grup > 0, set_qty bulat > 0, set_isi > 0, dan
--     bukan baris biaya. Kolom penanda saja → sp_vonny_gugur_baris (tidak membacanya) tidak menggugurkan cek
--     Vonny; isi_harga_list, total SP = PO, EHC tidak terpengaruh.
-- (2) trigger sol_set_usul (BEFORE INSERT, hanya saat rhj.usul = 'on'): baris SP yang disisipkan ulang oleh
--     putuskan_ubah membawa set_grup/set_nama/set_qty/set_isi dari usulan yang sedang diterapkan — dari
--     nilai_baru (layar baru mengirim kuncinya) atau, untuk usulan dari layar lama, dari nilai_lama (salinan
--     baris saat diajukan). Nilai yang tidak sah → tanpa tanda (keputusan GM tidak pernah gagal karenanya).
--     putuskan_ubah sendiri TIDAK diubah.
-- (3) Data lama (keputusan c): fungsi tandai_set_sp_lama() (tanpa grant ke peran aplikasi, dipanggil sekali di
--     sini dan BOLEH dijalankan ulang saat rilis) memberi tanda HANYA bila baris SP masih persis hasil pemecahan
--     set — pencocokan berjangkar menyusuri seluruh baris PO; urutan produk komponen sama dan Σ qty per komponen =
--     jumlah set × isi (boleh terpecah ke beberapa baris berurutan, seperti hasil pecahNettSen); ragu = berhenti.
--     Yang tidak cocok dibiarkan (tetap tampil per pcs). Diisi dengan session_replication_role = replica selama
--     pengisian saja: trigger baris (isi_harga_list menghitung ulang harga_list yang masih kosong, status SP,
--     total SP = PO, audit) TIDAK ikut menyala, jadi tidak ada angka, status, atau komisi yang bergeser.
--
-- Riwayat DEV: versi pertama berkas ini (blok DO, pencocok tanpa jangkar, tanpa revoke) dijalankan di DEV 8 Okt;
-- perbaikan hasil review dijalankan sebagai migrasi DEV "126b_set_di_sp_perbaikan" (fungsi + revoke). Hasil DEV sama
-- (1 SP, 4 baris). PROD cukup menjalankan berkas ini.
--
-- RILIS PROD (urutan): (1) putuskan/tolak dulu usul_ubah jenis 'sp' yang masih 'menunggu' bila memungkinkan
-- (bila tidak, fungsi (3) menyalin penanda ke nilai_lama-nya); (2) unggah index.html + jalankan berkas ini;
-- (3) sehari kemudian, sesudah semua tab dimuat ulang: `select public.tandai_set_sp_lama();`.
--
-- Tidak ada DROP.
-- ═══════════════════════════════════════════════════════════════════════

-- ── (1) kolom penanda set ───────────────────────────────────────────────
alter table public.sales_order_lines
  add column if not exists set_grup smallint,
  add column if not exists set_nama text,
  add column if not exists set_qty  numeric(12,2),
  add column if not exists set_isi  numeric(12,2);
comment on column public.sales_order_lines.set_grup is
  '#57 (berkas 126): nomor kelompok set dalam SP — tampilan saja; nilai & komisi tetap per pcs.';
comment on column public.sales_order_lines.set_qty is
  '#57: jumlah set kelompok ini. Utuh bila Σ qty per produk = set_qty × set_isi.';
comment on column public.sales_order_lines.set_isi is
  '#57: isi per set untuk produk baris ini (mis. 2 roda rem per set).';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sol_set_lengkap'
                    and conrelid = 'public.sales_order_lines'::regclass) then
    alter table public.sales_order_lines add constraint sol_set_lengkap check (
      (set_grup is null and set_nama is null and set_qty is null and set_isi is null)
      or (set_grup > 0 and set_qty > 0 and set_qty = trunc(set_qty) and set_isi > 0
          and jenis <> 'biaya' and char_length(coalesce(set_nama, '')) <= 200));
  end if;
end $$;

-- ── (2) tanda set ikut saat usulan "Minta ubah SP" diterapkan ────────────
-- putuskan_ubah (cabang SP) menghapus lalu menyisipkan ulang baris SP dari nilai_baru tanpa kolom set_*. Trigger
-- ini mengisi tandanya saat penyisipan itu (rhj.usul = 'on'), dari usulan yang SEDANG diterapkan (satu-satunya
-- usulan 'menunggu' untuk SP ini — indeks uu_menunggu_uniq): elemen nilai_baru.baris dengan urut & produk sama.
-- Elemen yang membawa kunci set_grup dipakai apa adanya (null = bukan set); usulan dari layar lama tanpa kunci itu
-- → tanda dari nilai_lama.baris (salinan baris saat diajukan; Minta ubah tidak menambah/menghapus baris). Nilai
-- yang tidak sah → tanpa tanda: keputusan GM tidak pernah gagal karena penanda tampilan.
-- putuskan_ubah sendiri TIDAK diubah (sesi EHC/komisi membangun #54 di atasnya).
create or replace function public.isi_set_baris_usul()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare v_baru jsonb; v_lama jsonb; x jsonb;
begin
  if coalesce(current_setting('rhj.usul', true), '') <> 'on' or new.set_grup is not null then
    return new;
  end if;
  select u.nilai_baru -> 'baris', u.nilai_lama -> 'baris' into v_baru, v_lama
    from public.usul_ubah u
   where u.jenis = 'sp' and u.ref_id = new.so_id and u.status = 'menunggu';
  if v_baru is null or jsonb_typeof(v_baru) <> 'array' then return new; end if;

  select e.v into x
    from jsonb_array_elements(v_baru) with ordinality e(v, o)
   where e.v->>'urut' = new.urut::text
     and nullif(e.v->>'product_id', '') is not distinct from new.product_id::text
   order by e.o limit 1;
  if x is null then return new; end if;
  if not (x ? 'set_grup') then
    x := null;
    if jsonb_typeof(v_lama) = 'array' then
      select e.v into x
        from jsonb_array_elements(v_lama) with ordinality e(v, o)
       where e.v->>'urut' = new.urut::text
         and nullif(e.v->>'product_id', '') is not distinct from new.product_id::text
       order by e.o limit 1;
    end if;
    if x is null then return new; end if;
  end if;

  if coalesce(new.jenis, 'barang') <> 'biaya'
     and coalesce(x->>'set_grup', '') ~ '^[1-9][0-9]{0,3}$'
     and coalesce(x->>'set_qty', '')  ~ '^[1-9][0-9]{0,9}(\.0+)?$'
     and coalesce(x->>'set_isi', '')  ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$'
     and coalesce(x->>'set_isi', '')  !~ '^0+(\.0+)?$' then
    new.set_grup := (x->>'set_grup')::smallint;
    new.set_nama := left(nullif(btrim(x->>'set_nama'), ''), 200);
    new.set_qty  := (x->>'set_qty')::numeric;
    new.set_isi  := (x->>'set_isi')::numeric;
  end if;
  return new;
end $function$;
create or replace trigger sol_set_usul
  before insert on public.sales_order_lines
  for each row execute function public.isi_set_baris_usul();
-- fungsi trigger security definer: tidak untuk dipanggil sebagai RPC (pengerasan berkas 75/84, linter 0028)
revoke all on function public.isi_set_baris_usul() from public, anon, authenticated;

-- ── (3) data lama: tanda set untuk SP yang barisnya masih persis hasil pemecahan set ──
-- Dibuat sebagai fungsi (tanpa grant ke peran aplikasi) supaya bisa DIJALANKAN ULANG saat rilis PROD sesudah index.html
-- baru diunggah dan semua tab dimuat ulang — SP yang sempat dibuat dari layar lama ikut ditandai. Idempoten: SP yang
-- sudah punya penanda dilewati.
-- Pencocokan BERJANGKAR (hasil review): seluruh baris PO ditelusuri menurut (urut, id) sambil memajukan posisi di
-- baris SP. Baris PO biasa memakan baris SP berurutan dengan produk & jenis sama bila Σ qty = qty PO; bila tidak ada
-- di posisi itu ia dilewati (mis. baris Rp 0 yang tidak ikut ke SP). Baris set hanya dicocokkan TEPAT di posisi itu;
-- begitu satu set tidak cocok, penandaan SP itu BERHENTI (ragu = jangan tandai) — tidak pernah menggeser posisi untuk
-- mencari kecocokan di belakang (dulu roda lepas yang kebetulan sama bisa ditandai sebagai set).
-- Usulan "Minta ubah SP" yang masih menunggu untuk SP yang baru ditandai: salinan baris lamanya (nilai_lama) diberi
-- penanda yang sama per id baris, supaya penanda tidak hilang saat usulan itu disetujui (trigger sol_set_usul).
create or replace function public.tandai_set_sp_lama()
returns integer
language plpgsql
set search_path = public
as $function$
declare
  s record; pl record; c record;
  a_id bigint[]; a_prod bigint[]; a_qty numeric[]; a_jenis text[];
  n int; pos int; kk int; g smallint;
  komp jsonb; perlu numeric; acc numeric; cocok boolean;
  tanda bigint[]; isi_tanda numeric[];
  n_set int := 0;
begin
  -- penanda saja: trigger baris tidak dinyalakan. SET LOCAL (bukan set_config): di Supabase hanya pernyataan SET
  -- yang diizinkan untuk parameter ini (supautils); dikembalikan ke origin di akhir fungsi.
  set local session_replication_role = replica;
  for s in
    select so.id, so.po_id
      from public.sales_orders so
     where so.po_id is not null
       and exists (select 1 from public.po_lines l
                    where l.po_id = so.po_id
                      and (l.set_id is not null or jsonb_typeof(l.set_komponen) = 'array'))
       and not exists (select 1 from public.sales_order_lines x where x.so_id = so.id and x.set_grup is not null)
     order by so.id
  loop
    select array_agg(x.id order by x.urut, x.id), array_agg(x.product_id order by x.urut, x.id),
           array_agg(x.qty order by x.urut, x.id), array_agg(x.jenis order by x.urut, x.id)
      into a_id, a_prod, a_qty, a_jenis
      from public.sales_order_lines x where x.so_id = s.id;
    n := coalesce(array_length(a_id, 1), 0);
    pos := 1; g := 0;
    for pl in
      select l.id, l.qty, l.product_id, coalesce(l.jenis, 'barang') as jenis, l.set_id, l.set_komponen, l.deskripsi,
             ps.nama as nama_set, (l.set_id is not null or coalesce(jsonb_typeof(l.set_komponen), '') = 'array') as adalah_set
        from public.po_lines l left join public.product_sets ps on ps.id = l.set_id
       where l.po_id = s.po_id
       order by l.urut, l.id
    loop
      if not pl.adalah_set then
        kk := pos; acc := 0;
        while kk <= n and acc < pl.qty and a_prod[kk] is not distinct from pl.product_id
              and coalesce(a_jenis[kk], 'barang') = pl.jenis loop
          acc := acc + a_qty[kk]; kk := kk + 1;
        end loop;
        if kk > pos and acc = pl.qty then pos := kk; end if;   -- tidak di posisi ini → dilewati, posisi tetap
        continue;
      end if;

      if not (pl.qty > 0 and pl.qty = trunc(pl.qty)) then exit; end if;
      -- komponen = snapshot saat PO disimpan; data lama tanpa snapshot → definisi set kini (= poKomponenSet di layar)
      komp := case when jsonb_typeof(pl.set_komponen) = 'array' then pl.set_komponen
                   else (select jsonb_agg(jsonb_build_object('product_id', c2.product_id, 'qty', c2.qty, 'urut', c2.urut)
                                          order by c2.urut, c2.id)
                           from public.product_set_components c2 where c2.set_id = pl.set_id) end;
      if komp is null or jsonb_array_length(komp) = 0 then exit; end if;
      select jsonb_agg(t.v order by coalesce(nullif(t.v->>'urut', '')::numeric, 0), t.o) into komp
        from jsonb_array_elements(komp) with ordinality t(v, o);

      kk := pos; cocok := true; tanda := '{}'; isi_tanda := '{}';
      for c in select (t.v->>'product_id')::bigint pid, (t.v->>'qty')::numeric q,
                      (select sum((t2.v->>'qty')::numeric) from jsonb_array_elements(komp) t2(v)
                        where t2.v->>'product_id' = t.v->>'product_id') isi
                 from jsonb_array_elements(komp) with ordinality t(v, o) order by t.o
      loop
        perlu := pl.qty * c.q; acc := 0;
        while kk <= n and acc < perlu and a_prod[kk] is not distinct from c.pid and coalesce(a_jenis[kk], 'barang') <> 'biaya' loop
          acc := acc + a_qty[kk];
          tanda := tanda || a_id[kk]; isi_tanda := isi_tanda || c.isi;
          kk := kk + 1;
        end loop;
        if acc <> perlu or not (c.isi > 0) then cocok := false; exit; end if;
      end loop;
      if not cocok then exit; end if;   -- ragu = berhenti: set ini dan sesudahnya tidak ditandai

      g := g + 1;
      update public.sales_order_lines x
         set set_grup = g,
             set_nama = left(coalesce(nullif(btrim(pl.deskripsi), ''), nullif(btrim(pl.nama_set), ''), 'Set'), 200),
             set_qty  = pl.qty,
             set_isi  = m.isi
        from unnest(tanda, isi_tanda) m(id, isi)
       where x.id = m.id;
      n_set := n_set + 1;
      pos := kk;
    end loop;

    if g > 0 then
      update public.usul_ubah u
         set nilai_lama = jsonb_set(u.nilai_lama, '{baris}', (
               select coalesce(jsonb_agg(case when coalesce(e.v->>'set_grup', '') <> '' then e.v
                                              else e.v || coalesce((select jsonb_build_object('set_grup', x.set_grup, 'set_nama', x.set_nama,
                                                                                              'set_qty', x.set_qty, 'set_isi', x.set_isi)
                                                                      from public.sales_order_lines x
                                                                     where x.so_id = s.id and x.id::text = e.v->>'id'), '{}'::jsonb) end
                                         order by e.o), '[]'::jsonb)
                 from jsonb_array_elements(u.nilai_lama->'baris') with ordinality e(v, o)))
       where u.jenis = 'sp' and u.ref_id = s.id and u.status = 'menunggu'
         and jsonb_typeof(u.nilai_lama->'baris') = 'array';
    end if;
  end loop;
  set local session_replication_role = origin;
  return n_set;
end $function$;
-- Hanya pemilik basis data (migrasi / SQL editor) — bukan RPC aplikasi. Sama dengan pengerasan berkas 75/84.
revoke all on function public.tandai_set_sp_lama() from public, anon, authenticated;

do $$ begin raise notice '#57: % kelompok set ditandai di SP lama', public.tandai_set_sp_lama(); end $$;
