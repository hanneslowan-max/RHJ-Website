-- ═══════════════════════════════════════════════════════════════════════
-- 113 · #34 Total baris PO bisa diedit — "penyesuaian pembulatan"
--
-- Customer sering membulatkan total baris di PO-nya (3 × 33.333,33 = 99.999,99
-- ditulis 100.000). Keputusan Hannes: total baris boleh diedit; selisihnya
-- terhadap qty × harga − diskon dicatat per baris sebagai penyesuaian (±),
-- paling banyak Rp 1.000 per baris. Aturan "tanpa pembulatan" tetap: tidak
-- ada yang dibulatkan sistem — angka customer dicatat apa adanya lewat kolom ini.
--
--   nilai baris PO = qty × harga − diskon + penyesuaian
--
-- SP tetap = PO: baris SP dari PO memecah nilai baris itu ke paling banyak 2
-- baris pcs yang jumlahnya persis (mekanisme yang sama dengan baris berdiskon,
-- spBarisDariPo), jadi harga per roda di bawah price list tetap ke GM.
-- Syaratnya sama dengan diskon (berkas 107): baris berpenyesuaian → qty × harga
-- harus habis dalam sen.
--
-- Diubah: po_lines (+penyesuaian & 3 CHECK), view po_ringkas (security_invoker
-- dipertahankan), periksa_baris_po_usul, putuskan_ubah (kolom ikut ditulis ulang
-- saat usulan ubah PO diterapkan — tidak boleh hilang).
-- Data lama: penyesuaian = 0 → nilai tidak berubah. Tidak ada data yang dihapus.
-- ═══════════════════════════════════════════════════════════════════════

alter table public.po_lines add column if not exists penyesuaian numeric(14,2) not null default 0;
comment on column public.po_lines.penyesuaian is
  '#34 (berkas 113): penyesuaian pembulatan total baris dari PO customer (±, maks Rp 1.000). '
  'Nilai baris = qty × harga − diskon + penyesuaian.';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'po_lines_penyesuaian_batas') then
    alter table public.po_lines add constraint po_lines_penyesuaian_batas check (abs(penyesuaian) <= 1000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'po_lines_penyesuaian_bruto_sen') then
    alter table public.po_lines add constraint po_lines_penyesuaian_bruto_sen
      check (penyesuaian = 0 or qty * harga = trunc(qty * harga, 2));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'po_lines_nilai_tak_negatif') then
    alter table public.po_lines add constraint po_lines_nilai_tak_negatif
      check (qty * harga
             - case when coalesce(diskon_tipe, 'rp') = 'persen' then qty * harga * coalesce(diskon, 0) / 100 else coalesce(diskon, 0) end
             + penyesuaian >= 0);
  end if;
end $$;

-- ── po_ringkas: nilai baris + penyesuaian (kolom & urutan sama) ──────────
create or replace view public.po_ringkas with (security_invoker = on) as
 SELECT p.id AS po_id,
    p.no_po,
    p.tanggal,
    p.nama_customer,
    p.sales_rep_id,
    p.ppn_kena,
    COALESCE(sum(n.nilai), 0::numeric) AS sub_total,
        CASE
            WHEN p.ppn_kena THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) * 0.11
            ELSE 0::numeric
        END AS ppn,
    COALESCE(sum(n.nilai), 0::numeric) +
        CASE
            WHEN p.ppn_kena THEN COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) * 0.11
            ELSE 0::numeric
        END AS grand_total,
    count(l.id) AS jumlah_baris,
    COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) AS dasar_ppn,
    COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'barang'::text), 0::numeric) AS total_barang,
    COALESCE(sum(n.nilai) FILTER (WHERE l.jenis = 'biaya'::text), 0::numeric) AS total_biaya
   FROM purchase_orders p
     LEFT JOIN po_lines l ON l.po_id = p.id
     LEFT JOIN LATERAL ( SELECT l.qty * l.harga -
                CASE
                    WHEN COALESCE(l.diskon_tipe, 'rp'::text) = 'persen'::text THEN l.qty * l.harga * COALESCE(l.diskon, 0::numeric) / 100::numeric
                    ELSE COALESCE(l.diskon, 0::numeric)
                END
                + COALESCE(l.penyesuaian, 0::numeric) AS nilai) n ON true   -- #34
  GROUP BY p.id;

-- ── pemeriksa baris usulan ubah PO: + penyesuaian ────────────────────────
create or replace function public.periksa_baris_po_usul(p_baris jsonb)
returns void
language plpgsql immutable set search_path = public as $function$
declare x jsonb; i int := 0; q numeric; h numeric; d numeric; t text; bruto numeric; v_set boolean; pj numeric;
begin
  for x in select value from jsonb_array_elements(coalesce(p_baris, '[]'::jsonb)) loop
    i := i + 1;
    q := nullif(x->>'qty', '')::numeric;
    h := coalesce(nullif(x->>'harga', '')::numeric, 0);
    d := coalesce(nullif(x->>'diskon', '')::numeric, 0);
    t := coalesce(nullif(x->>'diskon_tipe', ''), 'rp');
    pj := coalesce(nullif(x->>'penyesuaian', '')::numeric, 0);   -- #34
    -- #28: baris set = set master (set_id) ATAU set inline (set_komponen larik)
    v_set := nullif(x->>'set_id', '') is not null or jsonb_typeof(x->'set_komponen') = 'array';
    if q is null or q <= 0 then
      raise exception 'Baris %: qty harus lebih dari 0.', i;
    end if;
    if v_set and q <> trunc(q) then
      raise exception 'Baris %: jumlah set harus bilangan bulat.', i;
    end if;
    if h < 0 then
      raise exception 'Baris %: harga tidak boleh negatif.', i;
    end if;
    if t not in ('rp', 'persen') then
      raise exception 'Baris %: tipe diskon harus Rp atau persen.', i;
    end if;
    if d < 0 then
      raise exception 'Baris %: diskon tidak boleh negatif.', i;
    end if;
    bruto := q * h;
    if t = 'persen' then
      if d > 100 then
        raise exception 'Baris %: diskon % persen melebihi 100 persen.', i, trim_scale(d);
      end if;
      if bruto * d / 100 <> trunc(bruto * d / 100, 2) then
        raise exception 'Baris %: diskon % persen menghasilkan potongan % — tidak habis dalam sen. '
                        'Ubah persennya atau pakai diskon Rp.', i, trim_scale(d), trim_scale(bruto * d / 100);
      end if;
    else
      if d > bruto then
        raise exception 'Baris %: diskon Rp % melebihi nilai baris Rp %.', i, trim_scale(d), trim_scale(bruto);
      end if;
      if d <> trunc(d, 2) then
        raise exception 'Baris %: diskon Rp paling banyak 2 angka di belakang koma.', i;
      end if;
    end if;
    -- #34: penyesuaian pembulatan ±Rp 1.000, dalam sen, dan qty × harga harus habis dalam sen
    if abs(pj) > 1000 then
      raise exception 'Baris %: penyesuaian pembulatan paling banyak ±Rp 1.000 (diisi Rp %).', i, trim_scale(pj);
    end if;
    if pj <> trunc(pj, 2) then
      raise exception 'Baris %: penyesuaian pembulatan paling banyak 2 angka di belakang koma.', i;
    end if;
    if pj <> 0 and bruto <> trunc(bruto, 2) then
      raise exception 'Baris %: qty × harga = % tidak habis dalam sen, jadi total barisnya tidak bisa disesuaikan.', i, trim_scale(bruto);
    end if;
    if coalesce(nullif(x->>'jenis', ''), 'barang') = 'barang'
       and nullif(x->>'product_id', '') is null and not v_set then
      raise exception 'Baris %: baris barang harus menunjuk produk atau set.', i;
    end if;
  end loop;
end $function$;

-- ── putuskan_ubah: penyesuaian ikut ditulis ulang ────────────────────────
do $$
declare v text; w text;
begin
  v := pg_get_functiondef('public.putuskan_ubah(bigint, boolean, text)'::regprocedure);
  w := regexp_replace(v, 'diskon_tipe, jenis\)', 'diskon_tipe, jenis, penyesuaian)');
  if w = v then raise exception 'putuskan_ubah: daftar kolom insert po_lines tidak ditemukan.'; end if;
  v := w;
  w := regexp_replace(v, '(coalesce\(nullif\(o\.x->>''jenis'', ''''\), ''barang''\))(\s+from jsonb_array_elements\(b\) with ordinality)',
                      '\1,' || chr(10) || '             coalesce(nullif(o.x->>''penyesuaian'', '''')::numeric, 0)\2');   -- #34
  if w = v then raise exception 'putuskan_ubah: ekspresi select baris PO tidak ditemukan.'; end if;
  execute w;
end $$;
