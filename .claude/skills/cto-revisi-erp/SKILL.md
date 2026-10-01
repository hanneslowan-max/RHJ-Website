---
name: cto-revisi-erp
description: Kerjakan satu revisi ERP RHJ dari ujung ke ujung — uji tabrakan dengan ATURAN.md, migrasi db/NNN di Supabase DEV, uji dalam transaksi yang dibatalkan dengan simulasi peran, ubah index.html, uji layar, catat ATURAN/HANDOFF, commit & push. Pakai saat Hannes minta "kerjakan revisi #N", "tambahin fitur X di ERP", "perbaiki bug di PO/SP/penawaran", atau saat menjalankan verifikator sesudah "revisi selesai".
---

# Revisi ERP — alur baku

Satu revisi per satu. Jangan lompat langkah; laporkan bila ada langkah yang dilewati.

## 0. Siapkan konteks
- Baca `ATURAN.md` (A + B) dan `HANDOFF.md`. Catat nomor migrasi terakhir: `ls db | sort -V | tail -3`.
- Cari kode terkait: `grep -n "<nama fungsi/tab/RPC>" index.html db/*.sql`. Fungsi DB yang berlaku adalah
  definisi **terakhir** di migrasi bernomor tertinggi — cek juga langsung di DEV:
  `select pg_get_functiondef('public.<fungsi>'::regprocedure);`

## 1. Uji tabrakan (wajib, sebelum menulis kode)
Jalankan skill `cto-uji-dampak`. Bila hasilnya **menabrak** → berhenti, lapor ke Hannes, tunggu keputusan.
Bila tidak → lanjut.

## 2. Migrasi DB (bila perlu)
- Berkas baru `db/<nomor-berikut>-<slug-pendek>.sql`. Jangan pernah mengubah migrasi yang sudah jalan.
- Blok kepala wajib (contoh gaya `db/111`, `db/115`):
  ```sql
  -- ═══════════════════════════════════════════════════════════════════════
  -- 116 · #50 <judul revisi>
  --
  -- <apa yang berubah dan kenapa; aturan B yang ditegakkan>
  --
  -- Tidak ada data yang diubah.   ← atau sebutkan persis data apa yang berubah
  -- ═══════════════════════════════════════════════════════════════════════
  ```
- Fungsi `security definer` **selalu** `set search_path = public` dan memeriksa peran di awal
  (`public.peran_saya()`, `public.sales_rep_saya()`). Jangan percaya parameter dari klien untuk identitas.
- Penjagaan bisnis di DB (trigger/RPC/RLS), bukan hanya di layar.
- Uang dalam `numeric` sampai sen; **tidak ada pembulatan** (ATURAN B · Angka).

## 3. Uji migrasi di DEV — dalam transaksi yang dibatalkan
Ikuti `references/uji-migrasi.md`. Minimal:
- jalankan migrasi + skenario di dalam `begin; … rollback;` dulu;
- simulasikan **setiap peran yang relevan** (sales pemilik, sales lain, vonny, gm, owner, peran yang harus ditolak);
- untuk perubahan view/rumus/laporan: sidik md5 sebelum = sesudah pada data lama;
- baru sesudah lulus: `apply_migration` ke DEV (`project_id = eesdtbcualkdawhykchj`).

## 4. Front-end `index.html`
- Ikuti gaya sekitar: nama Indonesia, komentar seperlunya, helper format rupiah/angka yang sudah ada
  (titik ribuan, koma desimal, tampil sen).
- Semua daftar bisa diurutkan, kartu dashboard bisa diklik, filter default PO/SP "Semua" (ATURAN B).
- Pesan galat dari RPC ditampilkan apa adanya ke pengguna (jangan ditelan).

## 5. Uji layar
- Bila harness Playwright sesi sebelumnya tidak ada, buat di scratchpad (bukan di repo): buka `index.html`
  lewat `file://` atau server lokal, cegat semua request `*.supabase.co` dengan data tiruan — **tidak ada
  request keluar**. Chromium ada di `/opt/pw-browsers` (jangan `playwright install`).
- Uji desktop dan lebar HP (±390px), termasuk mengetik angka dengan keyboard HP.

## 6. Catat & kirim
- Aturan bisnis baru/berubah → tambahkan ke `ATURAN.md` B **dalam commit yang sama**.
- Perbarui tabel di `HANDOFF.md` (revisi, isi, migrasi) dan "Catatan untuk Hannes".
- Commit per revisi: `feat(#N): <ringkas> (DB NNN + FE)` atau `fix(#N): …`. Tanpa trailer Co-Authored-By.
- `git push -u origin <branch-sesi>`. PR hanya bila Hannes meminta.

## 7. Verifikator (hanya sesudah Hannes mengetik "revisi selesai")
Jalankan beberapa subagent paralel (Agent tool), masing-masing satu area — mis. (a) penawaran & pelanggan,
(b) PO & set & PPN, (c) SP/cek Vonny/pengiriman/batal, (d) komisi/GM/laporan & storage — dengan tugas:
cari cara pegawai atau orang luar melanggar ATURAN B lewat REST/RPC langsung (bukan lewat layar).
Lalu satu subagent **skeptis** per temuan untuk membantah, dan satu pengkritik kelengkapan. Hanya temuan
yang lolos skeptis yang diperbaiki — di satu migrasi perbaikan baru + FE — lalu uji ulang langkah 3–5.

## Laporan
Pakai format laporan di agent `cto` (Ringkasan / Yang berubah / Perlu keputusan / Risiko / Langkah berikut).
