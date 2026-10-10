# db/_snapshot — rujukan skema DEV (baca saja)

**Bukan migrasi. Jangan dijalankan.** Isinya salinan definisi dari Supabase DEV (`eesdtbcualkdawhykchj`),
diambil 10 Oktober 2026 (penanda versi DEV `rhj_rantai_versi()` = `139z`), supaya sesi berikutnya cukup
`grep` di repo tanpa query katalog DEV. Kebenaran tetap di DB live.

## Isi

| Berkas | Isi |
|---|---|
| `fungsi/<nama>.sql` | 239 fungsi `public` yang definisinya **tidak** ada di `db/*.sql` (berasal dari migrasi 1–58, yang tidak ada di repo). Persis keluaran `pg_get_functiondef`. 90 fungsi lain sudah ada di migrasi 59+. |
| `views/<nama>.sql` | 16 view yang tidak ada di `db/*.sql`; baris pertama = `reloptions` (mis. `security_invoker=on`). |
| `policies.sql` | **Semua** 150 policy RLS (public 136, storage 14). |
| `triggers.sql` | **Semua** trigger non-internal (public, storage, auth `on_auth_user_created`) + daftar event trigger. |

Catatan: banyak badan fungsi memakai akhir baris CRLF (begitu tersimpan di DB). `ada_huruf_non_latin` dan
`teks_tanpa_format` memuat karakter Unicode tak terlihat — disalin persis.

## Cara mencari

```bash
grep -rn "nama_fungsi" db/*.sql db/_snapshot/      # definisi yang berlaku = migrasi bernomor tertinggi;
                                                    # bila hanya ada di _snapshot, itulah definisinya
grep -n "on public.sales_orders" db/_snapshot/policies.sql db/_snapshot/triggers.sql
```

## Kapan diperbarui

- Migrasi baru yang mengubah objek yang ada di sini → setelah migrasinya jalan di DEV, perbarui berkas objek itu
  (salin ulang `pg_get_functiondef` / `pg_get_viewdef`), atau hapus berkasnya bila definisi terbarunya kini ada di
  `db/NNN-*.sql`.
- `policies.sql` dan `triggers.sql` dibuat ulang utuh bila ada migrasi yang menambah/mengubah policy atau trigger.
- Bila ragu snapshot sudah basi, bandingkan `rhj_rantai_versi()` di DEV dengan penanda di atas.
