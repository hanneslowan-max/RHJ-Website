# Uji migrasi di Supabase DEV

Semua lewat `mcp__Supabase__execute_sql` dengan `project_id = eesdtbcualkdawhykchj`.
Satu panggilan `execute_sql` = satu sesi; taruh `begin … rollback` di dalam **satu** panggilan.

## 1. Ambil pengguna uji per peran (sebagai postgres, sebelum ganti role)

```sql
select p.id, p.nama, p.peran, sr.id as sales_rep_id
from public.profiles p
left join public.sales_reps sr on sr.profile_id = p.id
where p.peran in ('owner','gm','sales','vonny','liesian','lenni','selfie','pending')
order by p.peran;
```

## 2. Simulasi satu peran di dalam transaksi yang dibatalkan

```sql
begin;
-- (opsional) jalankan isi migrasi baru di sini dulu, sebelum ganti role

select set_config('request.jwt.claims',
  json_build_object('sub', '<uuid-pengguna>', 'role', 'authenticated')::text, true);
set local role authenticated;

select public.peran_saya();                 -- pastikan peran yang disimulasikan benar
-- skenario: panggil RPC / insert / select seperti yang akan dilakukan klien lewat REST
-- contoh penolakan yang diharapkan:
-- select public.<rpc>(...);   → harus raise exception dengan pesan yang jelas

rollback;
```

Untuk menguji penolakan tanpa menghentikan seluruh skrip, bungkus dalam blok:

```sql
do $$ begin
  perform public.<rpc>(...);
  raise exception 'GAGAL UJI: seharusnya ditolak';
exception when others then
  if sqlerrm like 'GAGAL UJI%' then raise; end if;
  raise notice 'OK ditolak: %', sqlerrm;
end $$;
```

Uji minimal per revisi:
- peran yang **boleh** → berhasil, hasilnya benar sampai sen;
- peran yang **tidak boleh** (sales lain, lenni, selfie, pending, anon) → ditolak / 0 baris;
- jalur samping: insert/update langsung ke tabel (bukan lewat RPC) tidak bisa melangkahi gerbang.

Anon: `set local role anon;` tanpa claims → tidak boleh membaca/menulis apa pun selain yang memang publik.

## 3. Sidik md5 — angka lama tidak bergeser

Sebelum migrasi (dan di dalam transaksi sesudah migrasi), bandingkan:

```sql
select md5(string_agg(t::text, '|' order by t::text))
from (select * from public.<view_atau_fungsi_laporan>(...)) t;
```

Lakukan untuk setiap view/laporan/rumus yang disentuh (laporan penjualan, komisi, HPP/margin, total PO/SP).
Hasil harus **sama persis**. Bila beda dan memang disengaja → lapor ke Hannes sebelum apply.

## 4. Invariant yang selalu dicek sesudah migrasi yang menyentuh PO/SP

Grand total SP = grand total PO (sampai sen). Penjaganya `public.periksa_total_sp(p_so)` (definisi terbaru
di `db/114`) — ia `raise` bila tidak sama. Jalankan untuk semua SP ber-PO, di dalam transaksi:

```sql
begin;
do $$ declare r record; n int := 0; begin
  for r in select id from public.sales_orders where po_id is not null loop
    begin perform public.periksa_total_sp(r.id);
    exception when others then n := n + 1; raise notice 'SP %: %', r.id, sqlerrm; end;
  end loop;
  raise notice 'SP melanggar invariant: %', n;
end $$;
rollback;
```

Bandingkan jumlah pelanggar **sebelum dan sesudah** migrasi — tidak boleh bertambah.

## 5. Sesudah lulus
- `mcp__Supabase__apply_migration` ke DEV dengan nama sama dengan berkas `db/NNN-...`.
- `mcp__Supabase__get_advisors` (security & performance) — tidak boleh ada peringatan baru dari migrasi ini.
- Catat di laporan: skenario apa saja yang diuji, per peran, dan hasilnya.
