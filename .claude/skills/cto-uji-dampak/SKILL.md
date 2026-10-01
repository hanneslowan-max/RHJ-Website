---
name: cto-uji-dampak
description: Nilai sebuah permintaan perubahan ERP RHJ SEBELUM dikerjakan — uji tabrakan dengan ATURAN.md B dan penjagaan di DB (RLS/RPC/trigger), petakan dampak ke peran, angka, data lama, dan alur lain, lalu beri satu rekomendasi. Pakai saat Hannes bertanya "aman nggak kalau…", "apa dampaknya kalau…", "boleh nggak sales …", atau sebagai langkah 1 dari cto-revisi-erp.
---

# Uji tabrakan & dampak

Tujuan: Hannes memutuskan dengan informasi lengkap, dan tidak ada aturan bisnis yang bergeser diam-diam.

## Langkah

1. **Rumuskan permintaan** dalam satu kalimat: siapa (peran) melakukan apa, di layar/jalur mana, hasil yang diharapkan.
2. **Cocokkan dengan ATURAN.md B** — baca seluruh bagian B, bukan hanya subbab yang tampak relevan.
   Tandai setiap aturan yang disentuh: *tetap*, *diperluas*, *dikecualikan*, atau *dilanggar*.
3. **Cek penjagaan di DB** — aturan yang tertanam tapi belum tentu tertulis:
   ```bash
   grep -n "<tabel/kolom/RPC terkait>" db/*.sql | tail -40
   ```
   dan di DEV: policy (`select * from pg_policies where tablename = '<tabel>'`), trigger
   (`select tgname from pg_trigger where tgrelid = 'public.<tabel>'::regclass and not tgisinternal`),
   definisi fungsi terbaru (`pg_get_functiondef`).
4. **Petakan dampak** pada lima sumbu:

   | Sumbu | Pertanyaan |
   |---|---|
   | Peran & akses | Siapa yang jadi bisa melihat/mengubah sesuatu yang dulu tidak? Ada yang kehilangan akses? Jalur REST langsung ikut terbuka? |
   | Uang & angka | Komisi, tier, HPP/margin, price list, PPN/DPP, EHC, invariant SP = PO, laporan penjualan — ada yang bergeser? |
   | Gerbang | Approval GM, cek Vonny, cash-only (Riksa & Michael), konfirmasi pelanggan — ada yang bisa dilangkahi? |
   | Data lama | Baris lama perlu backfill? Ada yang berubah nilai? Bisa dibuktikan dengan md5? |
   | Alur lain | Penawaran → PO → SP → pengiriman → invoice → komisi: tahap sesudahnya masih konsisten? Mode PPN, set, batal parsial? |

5. **Putuskan status**:
   - **Tidak menabrak** → kerjakan (lanjut `cto-revisi-erp`).
   - **Menabrak** → BERHENTI. Jangan menulis migrasi atau kode.

## Format laporan bila menabrak

```
## Permintaan
<satu kalimat>

## Aturan yang ditabrak
- ATURAN B · <subbab>: "<kutipan aturan>" — <bagaimana permintaan melanggarnya>
- DB: <policy/trigger/RPC> di db/NNN — <penjagaan apa>

## Dampak bila dikerjakan apa adanya
- <peran/angka/gerbang/data lama yang terdampak, dengan contoh angka bila menyangkut uang>

## Rekomendasi
<satu opsi yang disarankan + alasan singkat>
Opsi lain: <a> (dampak …), <b> (dampak …)

## Yang dicatat di ATURAN B bila Hannes setuju
<rumusan aturan baru/pengecualian>
```

Contoh angka selalu konkret (mis. "PO 3 × 111.000 include → komisi dari DPP 300.000, tier 2%, bukan 5%").
Bila permintaan ambigu, ajukan **pertanyaan spesifik** sekaligus dengan rekomendasi default-nya.
