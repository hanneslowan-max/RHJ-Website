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
- Sales boleh **melihat** pelanggan sales lain di tab Pelanggan (#49) — baca saja: nama perusahaan, cabang (tidak ada kolom kota), industri, dan nama sales pemegang; tanpa HP, alamat, PIC, maupun transaksi. Pelanggan itu tetap tidak bisa dipakai di PO/penawaran/SP.
- Penawaran untuk pelanggan yang sudah bertuan **selalu** atas nama sales pemegangnya — berlaku untuk semua peran, termasuk owner/GM/staff/Vonny (#48). Bila memang perlu, pelanggannya dipindah dulu di tab Pelanggan.
- Vonny: membuat penawaran mewakili sales (wajib pilih sales), input PO & usul produk baru, membuat & mengubah **produk**, melihat order impor (tidak mengubah), cek SP. Hapus produk hanya owner. Pembayaran supplier tertutup bagi Vonny.
- Lenni: melihat PO & SP (baca saja).

### Penawaran
- Masa berlaku default kosong (tanpa batas).
- Setiap penawaran tercatat atas nama satu sales. Baris boleh berisi produk atau set, dengan spesifikasi; penawaran punya catatan.
- Penawaran boleh untuk pelanggan **baru** (#41): diisi langsung di form penawaran — wajib nama, alamat, HP; sales PIC = sales penawaran — dan ikut tersimpan ke data pelanggan saat penawaran disimpan. Nama/HP yang sudah ada di master ditolak (pilih dari daftar).
- Sebelum disimpan, penawaran ditampilkan dulu sebagai pratinjau dokumen (#39). Barang/set yang sudah dipilih bisa diganti (#43). Penawaran lama bisa dicari lalu disalin jadi penawaran baru — nomor baru, tanggal hari ini, harga dibandingkan dengan price list yang berlaku sekarang (#44).
- Nama perusahaan di penawaran diambil dari data pelanggan (sudah dirapikan: PT/CV di depan), bukan teks saat penawaran dibuat (#47).
- Mode harga penawaran (#42): **Exclude PPN** (bawaan — PPN 11% ditambahkan), **Include PPN** (harga sudah termasuk PPN: total = Σ qty × harga persis; DPP = total ÷ 1,11; PPN = total − DPP, tampil sampai sen), atau **Non-PPN**.
- Spesifikasi (#40): produk punya spesifikasi master (diubah owner/GM/staff/Vonny). Di penawaran kolom spesifikasi terisi otomatis dari spesifikasi **terakhir sales itu** untuk produk tersebut, atau dari master bila belum ada; tetap bisa diedit, dan setiap editan tersimpan lagi sebagai spesifikasi terakhir sales itu saat penawaran disimpan. Editan sales tidak mengubah master. Teks yang sama dengan master **bukan** editan — tidak dicatat, jadi revisi master tetap sampai ke sales itu.

### PO & set
- Pelanggan baru di form **PO** (#29) — nama yang tidak dipilih dari data pelanggan — ikut disimpan ke data pelanggan saat PO disubmit. Wajib: nama, alamat, No. HP, sales PIC (sales = dirinya). Nama/HP yang sudah ada di master ditolak (pilih dari daftar). **PO baru selalu menunjuk data pelanggan** — dijaga database, tidak hanya layar. Bentrok No. HP dengan pelanggan sales lain tidak menyebut nama pelanggan/sales-nya kepada sales.
- 1 set roda = 4 roda dari kategori & tipe sama; kombinasi sah: 4 rem, 4 hidup, 4 mati, 2 rem+2 hidup, 2 rem+2 mati, 2 hidup+2 mati. Di PO tampil "1 set @harga"; di SP dipecah ke pcs sesuai susunan set saat PO dibuat.
- Set bisa dibuat **langsung di baris** PO / penawaran / SP tanpa PO oleh penginputnya (termasuk sales) tanpa data master: pilih tipe roda + kombinasi, jumlah set (bulat), harga **per set** sesuai PO customer; komponen ditentukan sistem dan disimpan hanya di baris itu (#28). DB menolak isi set yang tidak sah.
- Harga per set dibagi ke tiap roda **sebanding price list** berlaku masing-masing, tepat sampai sen (grand total SP = PO tetap). Komponen tanpa price list → dibagi rata per pcs. Harga per roda di bawah price list tetap lewat approval GM.
- Sales **tidak** menulis data master set (Produk → Set roda); set master tetap boleh dipilih sebagai jalan pintas. Harga set master dibagi menurut harga nett definisinya.
- Mode PPN PO (#30) sama dengan penawaran: **Exclude** (bawaan), **Include** (harga di PO sudah termasuk PPN: grand = Σ baris persis; DPP = barang ÷ 1,11; PPN = barang − DPP), atau **Non-PPN**. Biaya/ongkos tidak pernah kena PPN. **SP selalu mengikuti mode PPN PO-nya** (tidak bisa dipilih lain; SP tanpa PO memilih sendiri; PO menyusul yang beda mode tidak bisa ditempel). Mode PO diubah lewat approval → SP-nya ikut; ditolak bila SP-nya sudah ber-invoice.
- Mode Include: harga nett & EHC di SP diketik termasuk PPN; price list, tier komisi, harga khusus, HPP/margin, nilai EHC, dan laporan penjualan (semua potongan) dihitung dari **DPP-nya (÷ 1,11)** — semua acuan itu memang tanpa PPN, jadi aturan komisi & gerbang GM tidak bergeser. Tanda "di bawah list" di penawaran, PO, dan SP juga dari DPP.
- Harga yang terisi otomatis dari price list (penawaran, PO, SP manual) pada mode Include = **price list × 1,11** (dinaikkan ke sen berikutnya bila tidak habis — hanya isian usulan, tidak pernah di bawah list). Mode PPN diganti → harga otomatis ikut; harga yang diketik orang tidak diubah. Ganti barang ke produk tanpa price list → harga otomatis dikosongkan.
- Mode PPN SP yang sudah ber-invoice tidak bisa diubah lewat jalur apa pun (sama dengan PO).
- Diskon baris PO: mode Rp atau %; % ≤ 100, Rp ≤ qty × harga, potongan habis dalam sen; baris berdiskon wajib qty × harga habis dalam sen.
- **Total baris PO bisa diubah** (#34) mengikuti PO customer yang dibulatkan. Selisihnya terhadap qty × harga − diskon dicatat sebagai *penyesuaian pembulatan* baris itu (±, paling banyak **Rp 1.000 per baris**, dalam sen; qty × harga wajib habis dalam sen). Sistem tetap tidak membulatkan apa pun — angka customer dicatat apa adanya. Qty/harga/diskon diubah → penyesuaian dilepas. Qty pecahan yang berdiskon/berpenyesuaian hanya sah bila nilai baris ÷ qty habis dalam sen (supaya SP-nya bisa dibuat). SP dari PO memecah nilai baris itu persis (maks. 2 baris pcs), jadi SP = PO tetap; harga per roda di bawah list tetap ke GM.
- Baris PO punya keterangan. Ubah PO lewat approval tidak boleh menghilangkan set, diskon, keterangan, penyesuaian pembulatan.
- Sales hanya bisa mengajukan ubah untuk PO miliknya.

### SP, cek Vonny, pengiriman, invoice
- **Invariant: grand total SP = grand total PO** (sampai sen).
- SP boleh tanpa PO (customer perorangan) dengan alasan; ditandai pembuat SP sebelum cek Vonny.
- Setiap SP wajib lolos **cek Vonny** sebelum ke pengiriman (Liesian). Hanya owner/GM/Vonny yang memutus. SP berubah sesudah lolos → kembali ke antrean cek.
- Tab Double Check memisahkan SP **menunggu cek**, **ditahan** (beserta alasannya), dan **baru diloloskan** (7 hari terakhir). SP yang diloloskan keluar dari antrean dan masuk Pengiriman; di Pengiriman SP itu ditandai "baru lolos cek Vonny" (3 hari) untuk Lie Sian (#35 #38).
- Sales melampirkan berkas PO customer saat input PO (boleh menyusul dari daftar PO). Mengganti lampiran yang sudah ada wewenang owner/GM. Lampiran hanya terbaca oleh yang boleh melihat PO-nya (peran impor tidak, lewat jalur apa pun). Berkas yang dilampirkan harus unggahan orang itu sendiri (owner/GM boleh berkas siapa pun) dan satu berkas hanya untuk satu PO. Vonny melihat no PO & lampirannya saat cek (#36).
- Semua SP harus bisa diberi kategori pelanggan (#37): SP yang pelanggannya belum ada di data pelanggan (mis. perorangan) ditautkan saat cek Vonny — nama lalu No. HP dicocokkan ke data pelanggan; bila belum ada, pelanggan dibuat (wajib HP & alamat, sales PIC = sales SP). Pelanggan yang dipegang **sales lain** tidak ditautkan (ditolak dengan pesan; owner/GM memindahkan pelanggannya dulu). Kategori yang sudah terisi di data pelanggan tidak ditimpa — Vonny diberi tahu. SP lama tanpa pelanggan (sudah lewat cek) ditautkan dari detail SP (owner/GM/Vonny).
- SP punya catatan untuk pengiriman.
- Pengiriman boleh bertahap (sebagian item/qty); setiap batch lewat gerbang yang sama (cek Vonny, konfirmasi pelanggan, harga GM, mode PO). Tulis surat jalan hanya lewat RPC.
- Batal: boleh batal sisa qty yang belum terkirim; qty terkirim tidak bisa dibatalkan. SP habis dibatalkan → SP batal & PO ikut batal (bila tidak ada SP lain). PO menampilkan nilai batal & efektif.

### Komisi & pembayaran
- Riksa & Michael: wajib cash (tidak bisa tempo lewat jalur apa pun), komisi flat 1% semua penjualan.
- Approval GM menampilkan harga nett SP, EHC, HPP, dan margin sebelum/sesudah EHC.

### EHC (budget entertain customer) — berkas 140, keputusan Hannes 6 Okt 2026
- EHC yang disisihkan di SP (dalam DPP, dipotong ke sen di bawahnya) adalah **saldo SP itu**. Klaim EHC = pemakaian saldo: boleh berkali-kali lintas bulan **selama komisi SP itu belum diklaim**. Satu klaim boleh memotong beberapa SP milik sales yang sama; tiap SP paling banyak sisa saldonya. SP yang belum ditautkan ke data pelanggan belum bisa dipakai.
- **Komisi SP diklaim → EHC SP tertutup**: sisa saldonya masuk **kas sales**. Sebelum klaim komisi, sales diberi peringatan sisa yang akan pindah.
- Setiap klaim berisi: untuk apa (transfer ke customer / entertain / ongkos bongkar muat), cara bayar (transfer langsung ke customer / sales bayar dulu → reimburse; kartu kredit perusahaan dicatat lewat statement finance — menyusul), tanggal transaksi (≤ hari ini), customer penerima, keterangan, dan **lampiran wajib** (bill / nota / bukti transfer; unggahan pengaju sendiri; satu berkas untuk satu klaim). *(Menggantikan aturan lama "klaim EHC tidak memerlukan lampiran bukti".)*
- Customer penerima ≠ customer SP → **lintas customer, wajib persetujuan GM** (diputus satu per satu, tidak lewat setujui massal; boleh juga lewat EHC cepat). Customer lain hanya yang dipegang sales itu atau belum bertuan.
- Transfer ke customer hanya ke rekening PIC aktif milik customer penerima, dan tidak boleh sama dengan rekening sales mana pun. PIC yang rekeningnya terkunci tidak bisa dipindah ke customer lain. Reimburse dibayar ke rekening sales pemilik klaim (diisi finance) — klaim reimburse tidak bisa disetujui GM sebelum rekening sales diisi. **Rekening tujuan dikunci saat GM menyetujui** (perubahan rekening sesudahnya tidak ikut ke klaim itu).
- **Periode EHC**: klaim yang dibuat tgl 19 bulan lalu s.d. **tgl 18** (WIB) masuk periode bulan ini. Sampai cutoff sales boleh mengubah/membatalkan klaimnya (#61); sesudahnya klaim terkunci untuk GM. *(berkas 141–143, keputusan Hannes 9 Okt 2026)*
- **Sesudah cutoff GM memeriksa per klaim**: setujui atau tolak (tolak wajib alasan). Klaim tanpa lampiran, dengan SP batal, atau yang saldo SP-nya tidak cukup tidak bisa disetujui. GM/owner **boleh memutus klaim yang ia buat/ubah sendiri** — siapa yang memutus selalu tercatat. Klaim yang sudah diputus tidak bisa diubah lagi. Klaim yang belum diputus tidak menghalangi klaim lain dan ikut pembayaran berikutnya.
- **Ditolak = final, tidak dibayar, saldonya kembali ke SP**; bila komisi SP itu sudah diklaim, saldo yang kembali masuk kas sales. Mengajukan ulang = klaim baru.
- **Finance membayar mulai tgl 20 (WIB)**: mengunci daftar bayar EHC **sekali per periode** — hanya klaim yang sudah disetujui GM dan **semua SP-nya lunas**; yang belum lunas/belum diputus ikut tgl 20 berikutnya. Transfer sesuai daftar → yang gagal dikeluarkan dari daftar (beralasan) → isi nomor referensi bank → klaim tercatat **ditransfer**. EHC tidak lagi lewat pengajuan transfer bulanan (komisi tetap lewat pengajuan).
- Owner/GM boleh membatalkan klaim yang uangnya belum keluar kapan saja (beralasan); klaim yang sudah masuk daftar bayar harus dikeluarkan finance dulu.
- Klaim boleh diajukan sebelum SP lunas (entertain bisa lebih dulu); uangnya baru keluar sesudah SP lunas — kecuali **EHC cepat** (darurat; menggantikan EHC dini): alasan + lampiran, diputus GM per klaim kapan saja, cair di luar jadwal dan boleh sebelum lunas. Menyetujui EHC cepat = menyetujui klaimnya. **Menolak EHC cepat hanya menolak pencairan cepatnya** — klaim tetap ikut pemeriksaan GM biasa sesudah tgl 18.
- Klaim tidak dihapus — dibatalkan (status batal + alasan), dan saldonya kembali. SP yang pernah dipakai klaim EHC tidak bisa dihapus. SP tidak bisa dibatalkan selama ada klaim EHC yang uangnya belum keluar atas SP itu, dan EHC SP tidak boleh turun di bawah yang sudah terpakai (batal qty, ubah baris, mode PPN).
- Hak sales atas klaim mengikuti **sales pemilik klaim**, bukan pemegang SP saat ini. **Klaim EHC** (nominal, alokasi, riwayat, lampiran, EHC cepat, putusan GM) hanya terbaca owner/GM/staff/finance/Lenni dan sales pemiliknya — **Vonny, Lie Sian, dan Ichi tidak melihat klaim EHC**. **Rekening** pada klaim (termasuk rekening sales pada reimburse) hanya terbaca owner/GM/finance dan sales pemiliknya.

### Angka & tampilan
- Tidak ada pembulatan di mana pun (termasuk PPN, komisi, laporan). Rupiah tampil dengan sen: "Rp 1.234,56".
- Semua angka memakai titik ribuan & koma desimal, diformat saat mengetik. Di layar sentuh, titik yang diketik dianggap koma desimal.
- Semua daftar bisa diurutkan (abjad, tanggal, angka). Semua kartu angka dashboard bisa diklik.
- Refresh halaman kembali ke tab terakhir. Filter default PO & SP = "Semua".

### Data master
- Nama pelanggan dirapikan otomatis: PT/CV/UD di depan, kapitalisasi seragam, singkatan dipertahankan; nama asli disimpan di nama_lama.
- Industri pelanggan: Otomotif, Non Otomotif, Bengkel Otomotif.
- Kategori produk: Roda, Pallet Mesh, Hospital, Filing Cabinet, Trolley, Hand Pallet, Lainnya.
- Hapus produk hanya owner (#32): produk yang belum pernah dipakai (PO, SP, penawaran, lead, set roda, komponen set di baris PO/penawaran, order impor, harga khusus, usulan ubah yang menunggu) dihapus permanen beserta price list/HPP-nya; yang sudah dipakai tidak dihapus, melainkan dinonaktifkan. Produk nonaktif tidak ditawarkan lagi di pilihan barang.
- Pencarian barang di form PO/penawaran/SP mencocokkan kode, merek, kelompok/seri, kategori, fungsi, bahan, ukuran, dan kode pabrik (#31).
- Baris SP yang produknya belum punya price list (mis. produk baru/usulan) tetap ke keputusan GM, tetapi alasannya ditulis "belum ada price list", bukan "di bawah price list" (#33).
