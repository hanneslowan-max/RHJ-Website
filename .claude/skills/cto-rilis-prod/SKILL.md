---
name: cto-rilis-prod
description: Siapkan paket rilis ERP RHJ dari DEV ke PROD — daftar migrasi berurutan, pemeriksaan pra-rilis, langkah backup, urutan unggah index.html, uji asap per peran, dan rencana mundur — untuk DIJALANKAN HANNES. Claude tidak pernah menyentuh PROD. Pakai saat Hannes minta "siapkan rilis", "naikkan ke prod", "migrasi mana yang belum di prod", atau sebelum merge branch revisi ke main.
---

# Paket rilis DEV → PROD

**Claude tidak pernah menjalankan apa pun di PROD (`hyjiuefqnsrofpebaydt`).** Hook di `.claude/settings.json`
memblokir MCP Supabase ke PROD — jangan mencari jalan lain. Keluaran skill ini adalah **dokumen paket rilis**
yang dijalankan Hannes (atau orang yang ditunjuk Hannes) di SQL editor Supabase PROD.

## 1. Kumpulkan isi rilis
- Branch sumber & commit: `git log --oneline main..<branch>`.
- Migrasi baru: `git diff --name-only main..<branch> -- db/ | sort -V`.
- Dari `HANDOFF.md`: migrasi mana yang sudah/belum pernah dijalankan di PROD (mis. "109–114 belum pernah di PROD").
- Perbaikan susulan (`114b`, dst.) — pastikan isinya sudah tercakup di berkas utamanya atau ikut diurutkan.

## 2. Pemeriksaan pra-rilis (di DEV & repo — boleh dijalankan Claude)
- [ ] Setiap migrasi di daftar sudah jalan di DEV (`list_migrations` DEV) dan lulus uji `cto-revisi-erp` langkah 3.
- [ ] `get_advisors` DEV (security + performance): tidak ada peringatan baru.
- [ ] Setiap migrasi **idempoten atau aman dijalankan sekali** (`create or replace`, `if not exists`, backfill bersyarat).
- [ ] Tidak ada migrasi yang menghapus data; yang mengubah data menyimpan cadangan (pola `*_sebelum_NNN`).
- [ ] `index.html`: objek `SITUS` masih memetakan `admin.palletmeshindonesia.com` → PROD dan
      `dev.palletmeshindonesia.com` → DEV; tidak ada URL/kunci DEV yang di-hardcode di jalur lain.
- [ ] Front-end baru tidak memanggil RPC/kolom yang belum ada di PROD sebelum migrasinya jalan.

## 3. Susun dokumen paket rilis
Tulis ke `rilis/RILIS-<tanggal>.md` (atau ke chat bila Hannes minta singkat) dengan isi:

```
# Rilis ERP <tanggal> — revisi <daftar>

## Ringkasan perubahan (bahasa bisnis)
- <per revisi: apa yang berubah bagi pengguna, peran yang terdampak>

## Sebelum mulai
1. Backup PROD: Supabase Dashboard → Database → Backups (catat waktu backup terakhir),
   atau minta Claude menyiapkan perintah pg_dump bila Hannes punya akses CLI.
2. Pilih waktu sepi (di luar jam input PO/SP). Umumkan ke tim.
3. Cek keadaan PROD — jalankan di SQL editor PROD, tempel hasilnya ke Claude:
   select version, name from supabase_migrations.schema_migrations order by version desc limit 15;

## Urutan eksekusi
| # | Berkas | Isi singkat | Ubah data? | Cek sesudahnya |
|---|---|---|---|---|
| 1 | db/109-... | ... | tidak | select ... |

## Unggah front-end
- Unggah index.html ke admin.palletmeshindonesia.com SESUDAH semua migrasi sukses.

## Uji asap sesudah rilis (per peran, ±10 menit)
- Owner: dashboard tampil, angka laporan bulan lalu sama dengan sebelum rilis (catat 3 angka sebelum).
- Sales: buat penawaran uji → hapus/batalkan; tidak melihat pelanggan sales lain selain daftar baca-saja.
- Vonny: antrean Double Check tampil.
- <skenario khusus revisi ini>

## Rencana mundur
- Front-end: unggah ulang index.html versi sebelumnya (simpan salinannya sebelum unggah).
- DB: <per migrasi: cara membalik — create or replace versi fungsi sebelumnya dari db/NNN lama;
  migrasi yang mengubah data → pulihkan dari tabel cadangan / backup>.
- Bila ragu: hentikan, jangan lanjut ke migrasi berikutnya, kabari Claude dengan pesan galat persisnya.
```

## 4. Sesudah Hannes menjalankan
- Minta hasil query cek & uji asap. Catat di `HANDOFF.md`: migrasi yang sudah di PROD + tanggal.
- Merge ke `main` / PR **hanya bila Hannes meminta**.
