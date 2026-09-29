-- 107 — #12 (temuan review G7): baris PO BERDISKON harus bernilai bruto (qty × harga) habis dalam sen.
--
-- Latar: sejak berkas 106 po_ringkas tidak lagi membulatkan, jadi nilai baris PO bisa berpecahan di bawah
-- sen (qty 2,5 × harga 1.000,01 = 2.500,025). Baris TANPA diskon tetap aman: SP menyalin qty & harga apa
-- adanya, nilainya identik. Baris BERDISKON dipecah ke SP sebagai qty × harga_nett, dan harga_nett
-- numeric(14,2) tidak bisa meniru pecahan di bawah sen → grand total SP ≠ PO, periksa_total_sp menolak
-- SP buatan aplikasi sendiri (contoh: 2,5 × 1.000,01 diskon Rp 99,98 → SP Rp 2.664,06 lawan PO Rp 2.664,05).
-- Potongan sudah wajib habis dalam sen (po_lines_diskon_sen), jadi cukup bruto yang habis dalam sen.
--
-- Aditif: data DEV per 29 Sep 2026 tidak ada yang melanggar (dicek sebelum VALIDATE). Baris set tidak
-- terdampak (qty set bulat × harga 2 desimal selalu habis dalam sen).
-- Membalik: alter table public.po_lines drop constraint po_lines_diskon_bruto_sen;

alter table public.po_lines
  add constraint po_lines_diskon_bruto_sen check (
    coalesce(diskon, 0) = 0 or qty * harga = trunc(qty * harga, 2)) not valid;
alter table public.po_lines validate constraint po_lines_diskon_bruto_sen;
