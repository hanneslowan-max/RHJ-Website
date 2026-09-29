# Serah-terima sesi — revisi 29–49 (belum dikerjakan)

Baca dulu `ATURAN.md` (aturan kerja: uji tabrakan dulu, lapor + rekomendasi, Hannes memutuskan).

## Status
- Revisi 1–28 selesai. 1–27 sudah di `main` (PR #1). #28 (set roda langsung di baris PO/penawaran/SP, migrasi `db/108`) + `ATURAN.md` ada di branch `claude/perbaikan-revisi-27`.
- DB DEV (`eesdtbcualkdawhykchj`) sudah menjalankan migrasi sampai `db/108`. PROD belum menerima apa pun (jangan disentuh).
- Revisi 29–49 BELUM dikerjakan. Diagnosa awal sempat dimulai lalu dihentikan (terlalu banyak prompt approval di sesi lama).

## Daftar revisi dari Hannes
29. Input customer baru: semua data yang diinput langsung tersimpan ke data pelanggan, beserta PIC sales.
30. Harga include PPN di PO.
31. Pencarian lebih luas, tidak hanya kode (contoh: `OSJB 5"` brand OSAKA harus ketemu dengan "osaka").
32. Belum bisa hapus produk.
33. Sales Darwis input produk baru → muncul notif harga di bawah list (PT Surya Panel). Cari masalahnya & perbaiki.
34. Total baris di nilai PO bisa diedit (customer biasa membulatkan).
35. Cek Vonny: tampilan berubah setelah dicek; setelah confirm hilang dari page Double Check dan SP diteruskan ke Pengiriman.
36. Upload lampiran PO saat sales upload PO; Vonny bisa lihat lampiran & no PO saat double check SP.
37. Customer perorangan di double check Vonny tidak ada pilihan kategori — semua pelanggan harus bisa dipilih kategorinya.
38. Setelah Vonny double check, SP masuk page Pengiriman untuk diproses Liesian.
39. Penawaran: preview sebelum disimpan.
40. Spesifikasi di penawaran auto-save & tertaut ke produk, tetap bisa diedit; setiap edit disimpan lagi.
41. Penawaran tidak bisa untuk customer baru.
42. Penawaran: kolom include PPN / exclude PPN / non PPN.
43. Item penawaran bisa diedit setelah dipilih.
44. Cari penawaran lama, lalu buat penawaran baru berdasarkan penawaran itu.
45. Tambah baris di penawaran: titik ribuan tidak muncul.
46. Input penawaran belum bisa — cari tahu kenapa.
47. Nama di penawaran: PT harus di depan (sekarang tampil di belakang).
48. Tidak bisa membuat penawaran ke customer yang dipegang sales lain.
49. Di page Pelanggan, sales tetap bisa MELIHAT customer sales lain (baca saja, tidak bisa edit).

## Hasil cek tabrakan & rekomendasi (menunggu jawaban Hannes)
- Tidak menabrak (langsung kerjakan): 31, 33, 35/38, 36, 39, 41, 43, 44, 45, 46, 47, 48.
- #34 (menabrak "tanpa pembulatan"): total baris boleh diedit; selisih dicatat sebagai "penyesuaian pembulatan" per baris (±), batas ± Rp 1.000 per baris; SP tetap = PO; gerbang GM tetap.
- #30 & #42: mode Include / Exclude / Non-PPN di PO & penawaran. Include: grand total = Σ qty×harga persis; DPP = total ÷ 1,11; PPN = total − DPP (tampil sampai sen). SP mengikuti mode PO.
- #40 (menabrak "sales tidak menulis master produk"): kolom spesifikasi di produk; di penawaran terisi otomatis & bisa diedit; editan sales disimpan sebagai "spesifikasi terakhir sales itu" per produk; master hanya diubah owner/staf impor/Vonny.
- #49 (menabrak "sales hanya lihat miliknya"): daftar baca-saja berisi nama perusahaan, kota, industri, nama sales pemegang — tanpa HP/alamat/transaksi; tetap tidak bisa dipilih di PO/penawaran.
- #32: produk belum pernah dipakai → owner bisa hapus permanen; sudah dipakai → otomatis dinonaktifkan.
- #37 & #29: customer perorangan juga selalu disimpan ke data pelanggan (HP, alamat, sales PIC) agar kategori bisa dipilih.
- Pertanyaan terbuka #29: customer baru diinput dari form mana (PO / SP / keduanya)? Data wajib selain nama, alamat, HP, sales PIC (NPWP? email?)?
