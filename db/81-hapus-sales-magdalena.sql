-- Berkas 81: hapus master sales "Magdalena" (id 14, nonaktif) agar tak muncul di dropdown.
-- Prasyarat (berkas 80): SELURUH referensi ke id 14 = 0 → DELETE tak meng-orphan data.
--   Pelanggan & transaksinya tetap ada, berpindah ke Menik (id 6). Riwayat di audit_log + berkas 80.
--   Reversibel: insert ulang rep bila kelak diperlukan.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

delete from public.sales_reps where id = 14 and aktif = false;
