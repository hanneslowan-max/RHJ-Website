---
name: cto-audit-keamanan
description: Audit keamanan & akses data ERP RHJ di Supabase DEV + index.html — pintu anon, RLS yang bocor antar peran (HPP, price list, komisi, rekening, pelanggan sales lain), fungsi security definer tanpa cek peran/search_path, gerbang GM/Vonny/cash-only yang bisa dilangkahi lewat REST, storage, akun pending, CSP. Pakai saat Hannes minta "audit keamanan", "cek akses sales", "siapa bisa lihat HPP", atau rutin tiap kuartal / sesudah banyak migrasi baru.
---

# Audit keamanan ERP

Semua query ke **DEV** (`eesdtbcualkdawhykchj`). Bila skill akun `audit-erp-internal` tersedia, pakai juga
metodenya untuk audit mendalam; skill ini adalah daftar periksa rutin yang bisa diulang.

Prinsip: **anggap penyerang memanggil REST/RPC langsung** dengan token perannya sendiri — layar tidak dihitung
sebagai penjaga. Setiap temuan harus dibuktikan dengan skenario uji (simulasi peran, lihat
`.claude/skills/cto-revisi-erp/references/uji-migrasi.md`), bukan dugaan.

## 1. Inventaris otomatis
```sql
-- tabel public tanpa RLS
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

-- hak anon pada tabel/view
select table_name, privilege_type from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public';

-- fungsi yang bisa dieksekusi anon
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');

-- security definer tanpa search_path terkunci
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');

-- security definer yang tidak memeriksa peran sama sekali (tinjau manual satu per satu)
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and pg_get_functiondef(p.oid) !~* '(peran_saya|sales_rep_saya|auth\.uid)';

-- policy yang longgar
select tablename, policyname, cmd, roles, qual, with_check from pg_policies
where schemaname = 'public' and (qual = 'true' or with_check = 'true' or 'anon' = any(roles));
```
Plus `mcp__Supabase__get_advisors` (security & performance).

## 2. Matriks data sensitif × peran
Uji dengan simulasi peran; isi tabel ini di laporan. Kolom "Boleh" adalah acuan awal — kebenaran akhirnya
ATURAN B dan keputusan Hannes. Bila policy di DB berbeda dari acuan ini, laporkan sebagai temuan untuk
diputuskan, jangan langsung "diperbaiki". (Migrasi 1–58 tidak ada di repo — baca policy langsung dari
`pg_policies` DEV, bukan dari `db/`.)

| Data | Boleh | Harus ditolak |
|---|---|---|
| HPP (`product_costs`), margin di konteks GM | owner, gm (sesuai aturan) | sales, vonny, lenni, liesian, selfie, pending |
| Price list (`price_list`) | sesuai ATURAN B | pending, anon |
| Komisi & klaim (`komisi_klaim*`), rekening (`sales_rep_rekening*`) | owner/finance + sales pemiliknya | sales lain |
| Pelanggan (`customers`) | sales pemilik + tanpa pemilik; RPC baca-saja `pelanggan_sales_lain` (nama, cabang, industri, sales) | HP/alamat/PIC/transaksi pelanggan sales lain |
| PO/SP/penawaran | sales pemiliknya; lenni baca saja | sales lain; peran impor |
| Lampiran PO, bukti EHC/komisi (storage `dokumen`, awalan po/, ehc/, komisi/) | sesuai policy `rhj_*` | selfie (peran impor), sales lain |
| Pembayaran supplier (`payments`, `orders`) | sesuai ATURAN B | vonny, sales |

## 3. Gerbang yang tidak boleh bisa dilangkahi
- Approval GM untuk harga di bawah list / tanpa price list — coba update baris SP langsung.
- Cek Vonny sebelum pengiriman; SP berubah sesudah lolos → kembali ke antrean.
- Cash-only (Riksa & Michael) — coba set tempo lewat semua jalur (insert, update, RPC).
- Surat jalan hanya lewat RPC; qty terkirim tidak bisa dibatalkan; mode PPN terkunci sesudah invoice.
- Penawaran untuk pelanggan bertuan selalu atas nama sales pemegangnya.

## 4. Akun & sesi
- Akun `pending` tidak bisa membaca apa pun selain profilnya; `nonaktif` diperlakukan sama.
- Daftar pengguna aktif per peran — tandai akun yang lama tidak login (bila tersedia di auth) untuk ditinjau Hannes.

## 5. Front-end `index.html`
- CSP di `<meta>` masih ketat (`connect-src https://*.supabase.co`, tanpa `unsafe-eval`, `object-src 'none'`).
- Tidak ada `innerHTML` dengan data pengguna tanpa escape (cari `innerHTML` + interpolasi).
- Hanya kunci **publishable** di berkas; tidak ada service-role key / secret di repo (`grep -n "service_role\|sb_secret" -r .`).

## Laporan
Urutkan temuan dari paling berbahaya. Per temuan: **siapa** bisa **apa**, **jalur** (REST/RPC/storage),
**bukti** (query uji & hasilnya), **dampak bisnis** (uang/data bocor), **perbaikan yang disarankan**.
Perbaikan dikerjakan lewat `cto-revisi-erp` (migrasi baru) — bila perbaikannya mengubah aturan bisnis,
lapor dulu ke Hannes lewat `cto-uji-dampak`.
