---
name: cto-laporan
description: Susun laporan CTO untuk Hannes — kesehatan ERP RHJ (DEV vs PROD, migrasi tertunda, advisor Supabase, insiden), progres revisi, skor KPI teknologi, risiko teratas, dan roadmap 3–6 bulan dengan satu rekomendasi prioritas. Pakai saat Hannes minta "laporan CTO", "status sistem", "roadmap teknologi", "apa prioritas IT bulan ini", atau evaluasi KPI.
---

# Laporan CTO

Ditulis untuk pemilik bisnis: singkat, bahasa bisnis, setiap angka ada sumbernya, satu rekomendasi jelas.

## 1. Kumpulkan data (jangan menebak)
| Data | Sumber |
|---|---|
| Revisi selesai / berjalan / menunggu keputusan | `HANDOFF.md`, `git log --oneline -30`, branch `claude/*` yang belum di-merge (`git branch -r`) |
| Migrasi di DEV vs PROD | `ls db | sort -V`, `list_migrations` DEV, catatan PROD di `HANDOFF.md` (PROD tidak di-query) |
| Peringatan keamanan/performa | `get_advisors` DEV (security + performance) |
| Galat & insiden | `query_logs` DEV; catatan insiden di `HANDOFF.md` |
| Aturan bisnis baru periode ini | `git log -p --since=<awal periode> -- ATURAN.md` |
| Ukuran & kompleksitas | `wc -l index.html`, jumlah migrasi, jumlah RPC (`select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where nspname='public'`) |

Bila sebuah data tidak bisa diambil, tulis "tidak tersedia" — jangan diisi perkiraan.

## 2. Skor KPI (dari job description CTO)
| Area | Indikator | Target | Nilai periode ini | Status |
|---|---|---|---|---|
| Kualitas rilis | Rilis ke PROD tanpa uji DEV | 0 | | |
| Kualitas rilis | Bug kritis selesai | ≤ 1×24 jam | | |
| Keamanan | Audit akses terakhir | ≤ 3 bulan lalu | | |
| Keamanan | Kebocoran data antar peran terbukti | 0 | | |
| Akurasi | Pelanggar invariant SP = PO | 0 | | |
| Kecepatan | Rata-rata hari revisi disetujui → selesai di DEV | (disepakati Hannes) | | |
| Utang rilis | Migrasi sudah di DEV tapi belum di PROD | sekecil mungkin | | |

Status: ✅ tercapai · ⚠️ perlu perhatian · ❌ meleset — selalu dengan satu kalimat sebab.

## 3. Struktur laporan
```
# Laporan CTO — <periode>

## Inti (3 poin)
- <kondisi sistem dalam satu kalimat>
- <pencapaian terpenting>
- <risiko/keputusan terpenting yang dibutuhkan dari Hannes>

## Kesehatan sistem
<tabel KPI>

## Progres revisi
| Revisi | Isi | Status (DEV/PROD/menunggu) |

## Risiko teratas
1. <risiko> — dampak bisnis — mitigasi yang disarankan

## Roadmap 3–6 bulan
| Bulan | Inisiatif | Manfaat bisnis | Perkiraan usaha |
Contoh tema: kejar utang rilis PROD; audit keamanan kuartalan; pecah index.html bila mulai menghambat;
uji otomatis (harness Playwright + skenario SQL per peran) masuk repo; dashboard manajemen; otomasi laporan.

## Rekomendasi
<satu prioritas utama periode berikut + alasan>
```

Bila Hannes ingin laporan dibagikan ke tim, tawarkan menerbitkannya sebagai halaman/dokumen.
