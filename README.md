# RHJ-Website — ERP Internal PT Roda Hammerindo Jaya

Aplikasi web internal (ERP) untuk operasional PT Roda Hammerindo Jaya.

## Struktur

| Path          | Isi                                                        |
|---------------|------------------------------------------------------------|
| `index.html`  | Frontend single-file (vanilla JS, tanpa framework/build)   |
| `db/`         | Arsip berkas migrasi database (Supabase/Postgres)          |
| `infodb.md`   | Catatan skema database                                     |

## Lingkungan

- **Dev**: `dev.palletmeshindonesia.com` → database Supabase DEV
- **Prod**: `admin.palletmeshindonesia.com` → database Supabase PROD

Pemilihan database dilakukan otomatis berdasarkan hostname.

## Alur perubahan kode

1. Kerja di branch terpisah (bukan langsung di `main`).
2. Commit & push ke branch tersebut.
3. Review, lalu merge ke `main` oleh pemilik proyek.
4. Deploy `index.html` ke host dev untuk diuji, baru ke prod.
