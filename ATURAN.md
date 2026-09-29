# Aturan Kerja & Aturan Bisnis ERP RHJ

Berkas ini dibaca Claude sebelum mengerjakan setiap revisi. Pemilik keputusan: Hannes.

## A. Cara kerja revisi

1. **Uji tabrakan dulu.** Setiap revisi yang diminta Hannes dicek terhadap semua aturan di bagian B (dan aturan yang tertanam di RLS/RPC/trigger DB) sebelum dikerjakan.
2. **Kalau menabrak:** berhenti, lapor ke Hannes — aturan mana yang ditabrak, dampaknya, dan rekomendasi solusi. Hannes boleh menerima rekomendasi atau memutuskan sendiri. Keputusan Hannes dicatat di bagian B (aturan lama diubah/diberi pengecualian), baru dikerjakan.
3. **Kalau tidak menabrak:** langsung kerjakan, satu revisi per satu.
4. **SQL:** query & migrasi ke DEV (`eesdtbcualkdawhykchj`) dijalankan tanpa minta persetujuan, **kecuali** perubahannya menabrak aturan di bagian B — itu wajib dilaporkan dulu (lihat poin 2).
5. **PROD (`hyjiuefqnsrofpebaydt`) tidak pernah disentuh.** DEV boleh diubah asal tidak menghilangkan data.
6. Kerja & push di branch sesi `claude/...`; merge ke `main` keputusan Hannes. Commit tanpa trailer Co-Authored-By. PR hanya bila diminta.
7. Verifikator menyeluruh dijalankan hanya setelah Hannes mengetik **"revisi selesai"**.
8. Setiap aturan bisnis baru/berubah ditambahkan ke bagian B dalam commit yang sama.

## B. Aturan bisnis yang berlaku

### Akses & peran
- Keamanan ditegakkan di DB (RLS/RPC/trigger); FE hanya menyembunyikan tombol.
- Sales hanya melihat & mengolah data miliknya (customer, penawaran, PO, SP). Customer tanpa pemilik boleh dipakai; customer milik sales lain tidak — sistem memberi peringatan pemiliknya.
- Vonny: membuat penawaran mewakili sales (wajib pilih sales), input PO & usul produk baru, membuat & mengubah **produk**, melihat order impor (tidak mengubah), cek SP. Hapus produk hanya owner. Pembayaran supplier tertutup bagi Vonny.
- Lenni: melihat PO & SP (baca saja).

### Penawaran
- Masa berlaku default kosong (tanpa batas).
- Setiap penawaran tercatat atas nama satu sales. Baris boleh berisi produk atau set, dengan spesifikasi; penawaran punya catatan.

### PO & set
- 1 set roda = 4 roda dari kategori & tipe sama; kombinasi sah: 4 rem, 4 hidup, 4 mati, 2 rem+2 hidup, 2 rem+2 mati, 2 hidup+2 mati. Di PO tampil "1 set @harga"; di SP dipecah ke pcs sesuai susunan set saat PO dibuat.
- Set bisa dibuat **langsung di baris** PO / penawaran / SP tanpa PO oleh penginputnya (termasuk sales) tanpa data master: pilih tipe roda + kombinasi, jumlah set (bulat), harga **per set** sesuai PO customer; komponen ditentukan sistem dan disimpan hanya di baris itu (#28). DB menolak isi set yang tidak sah.
- Harga per set dibagi ke tiap roda **sebanding price list** berlaku masing-masing, tepat sampai sen (grand total SP = PO tetap). Komponen tanpa price list → dibagi rata per pcs. Harga per roda di bawah price list tetap lewat approval GM.
- Sales **tidak** menulis data master set (Produk → Set roda); set master tetap boleh dipilih sebagai jalan pintas. Harga set master dibagi menurut harga nett definisinya.
- Diskon baris PO: mode Rp atau %; % ≤ 100, Rp ≤ qty × harga, potongan habis dalam sen; baris berdiskon wajib qty × harga habis dalam sen.
- Baris PO punya keterangan. Ubah PO lewat approval tidak boleh menghilangkan set, diskon, keterangan.
- Sales hanya bisa mengajukan ubah untuk PO miliknya.

### SP, cek Vonny, pengiriman, invoice
- **Invariant: grand total SP = grand total PO** (sampai sen).
- SP boleh tanpa PO (customer perorangan) dengan alasan; ditandai pembuat SP sebelum cek Vonny.
- Setiap SP wajib lolos **cek Vonny** sebelum ke pengiriman (Liesian). Hanya owner/GM/Vonny yang memutus. SP berubah sesudah lolos → kembali ke antrean cek.
- SP punya catatan untuk pengiriman.
- Pengiriman boleh bertahap (sebagian item/qty); setiap batch lewat gerbang yang sama (cek Vonny, konfirmasi pelanggan, harga GM, mode PO). Tulis surat jalan hanya lewat RPC.
- Batal: boleh batal sisa qty yang belum terkirim; qty terkirim tidak bisa dibatalkan. SP habis dibatalkan → SP batal & PO ikut batal (bila tidak ada SP lain). PO menampilkan nilai batal & efektif.

### Komisi & pembayaran
- Riksa & Michael: wajib cash (tidak bisa tempo lewat jalur apa pun), komisi flat 1% semua penjualan.
- Approval GM menampilkan harga nett SP, EHC, HPP, dan margin sebelum/sesudah EHC.
- Klaim EHC tidak memerlukan lampiran bukti.

### Angka & tampilan
- Tidak ada pembulatan di mana pun (termasuk PPN, komisi, laporan). Rupiah tampil dengan sen: "Rp 1.234,56".
- Semua angka memakai titik ribuan & koma desimal, diformat saat mengetik. Di layar sentuh, titik yang diketik dianggap koma desimal.
- Semua daftar bisa diurutkan (abjad, tanggal, angka). Semua kartu angka dashboard bisa diklik.
- Refresh halaman kembali ke tab terakhir. Filter default PO & SP = "Semua".

### Data master
- Nama pelanggan dirapikan otomatis: PT/CV/UD di depan, kapitalisasi seragam, singkatan dipertahankan; nama asli disimpan di nama_lama.
- Industri pelanggan: Otomotif, Non Otomotif, Bengkel Otomotif.
- Kategori produk: Roda, Pallet Mesh, Hospital, Filing Cabinet, Trolley, Hand Pallet, Lainnya.
