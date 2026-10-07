-- ═══════════════════════════════════════════════════════════════════════
-- 125 · #53 kelompok produk baru "RHAJA Series" untuk RHJ R & RHJ PP (data)
--
-- Keputusan Hannes (7 Okt): RHJ R dan RHJ PP masih tampil di kelompok RHJ (terpecah) → buat kelompok baru RHAJA
-- dan masukkan keduanya. Di DEV ini SUDAH dilakukan Hannes sendiri (1 Sep 2026, Ubah massal → "RHAJA Series",
-- 59 produk) tetapi tidak pernah masuk berkas db/ — jadi PROD belum berubah. Berkas ini membawa perubahan
-- yang sama ke PROD, persis daftar DEV:
--   · dicocokkan per PASANGAN (kode, kelompok lama) — produk yang kelompoknya sudah lain / sudah RHAJA tidak
--     tersentuh (idempoten; di DEV kelompoknya tidak berubah lagi);
--   · kolom bahan diisi (hanya bila kosong) dari keterangan yang dulu ada di nama kelompok lama — supaya
--     pencarian "karet"/"nylon" tetap menemukan produk ini (pencarian membaca bahan). Pilihan bahan yang sah
--     hanya CB / Karet / Nylon / Polyurethane (products_bahan_sah): RHJ R → Karet, RHAJA PP grey rubber →
--     Karet, PP 8" M (nylon/PP) & Roller Phinoliq → Nylon; PP biasa dibiarkan kosong ("PP" sudah ada di kodenya).
-- Merek (RHJ-TW), kategori (Roda), tipe roda untuk set, price list, dan komisi TIDAK berubah.
-- ═══════════════════════════════════════════════════════════════════════

with peta(kode, kel_lama, bahan) as (values
  ('2" H', 'RHAJA PP — RHAJA GREY RUBBER SCREW HOLD', 'Karet'),
  ('2" R', 'RHAJA PP — RHAJA GREY RUBBER SCREW HOLD', 'Karet'),
  ('RHJ BLACK PP 2" H', '2 Inch PP', null),
  ('RHJ BLACK PP 2" R', '2 Inch PP', null),
  ('RHJ BLACK PP 2" SC H', 'RHJ 2 Inch', null),
  ('RHJ BLACK PP 2" SC R', 'RHJ 2 Inch', null),
  ('RHJ PP 2" H', '2 Inch PP', null),
  ('RHJ PP 2" M', '2 Inch PP', null),
  ('RHJ PP 2" R', '2 Inch PP', null),
  ('RHJ PP 3" H', 'RHAJA — PP', null),
  ('RHJ PP 3" H - NO COVER', 'RHAJA — PP', null),
  ('RHJ PP 3" M', 'RHAJA — PP', null),
  ('RHJ PP 3" M - NO COVER', 'RHAJA — PP', null),
  ('RHJ PP 3" R', 'RHAJA — PP', null),
  ('RHJ PP 3" R - NO COVER', 'RHAJA — PP', null),
  ('RHJ PP 3" WO', 'RHAJA — PP', null),
  ('RHJ PP 3" WO - NO COVER', 'RHAJA — PP', null),
  ('RHJ PP 4" H', 'RHAJA — PP', null),
  ('RHJ PP 4" M', 'RHAJA — PP', null),
  ('RHJ PP 4" R', 'RHAJA — PP', null),
  ('RHJ PP 4" WO', 'RHAJA — PP', null),
  ('RHJ PP 5" H', 'RHAJA — PP', null),
  ('RHJ PP 5" M', 'RHAJA — PP', null),
  ('RHJ PP 5" R', 'RHAJA — PP', null),
  ('RHJ PP 5" WO', 'RHAJA — PP', null),
  ('RHJ PP 6" H', 'RHAJA — PP', null),
  ('RHJ PP 6" M', 'RHAJA — PP', null),
  ('RHJ PP 6" R', 'RHAJA — PP', null),
  ('RHJ PP 6" WO', 'RHAJA — PP', null),
  ('RHJ PP 8" H', 'RHAJA — PP', null),
  ('RHJ PP 8" M', 'RHAJA — nylon/PP', 'Nylon'),
  ('RHJ PP 8" R', 'RHAJA — PP', null),
  ('RHJ R 2" H', 'RHJ 2 Inch', 'Karet'),
  ('RHJ R 2" M', 'RHJ 2 Inch', 'Karet'),
  ('RHJ R 2" R', 'RHJ 2 Inch', 'Karet'),
  ('RHJ R 3" H', 'RHAJA — karet', 'Karet'),
  ('RHJ R 3" M', 'RHAJA — karet', 'Karet'),
  ('RHJ R 3" R', 'RHAJA — karet', 'Karet'),
  ('RHJ R 3" WO', 'RHAJA — karet', 'Karet'),
  ('RHJ R 4" H', 'RHAJA — karet', 'Karet'),
  ('RHJ R 4" M', 'RHAJA — karet', 'Karet'),
  ('RHJ R 4" R', 'RHAJA — karet', 'Karet'),
  ('RHJ R 4" WO', 'RHAJA — karet', 'Karet'),
  ('RHJ R 5" H', 'RHAJA — karet', 'Karet'),
  ('RHJ R 5" M', 'RHAJA — karet', 'Karet'),
  ('RHJ R 5" R', 'RHAJA — karet', 'Karet'),
  ('RHJ R 5" WO', 'RHAJA — karet', 'Karet'),
  ('RHJ R 5" WO (bushing + cover)', 'RHAJA — karet', 'Karet'),
  ('RHJ R 6" H', 'RHAJA — karet', 'Karet'),
  ('RHJ R 6" M', 'RHAJA — karet', 'Karet'),
  ('RHJ R 6" R', 'RHAJA — karet', 'Karet'),
  ('RHJ R 6" WO', 'RHAJA — karet', 'Karet'),
  ('RHJ R 6" WO (bushing + cover)', 'RHAJA — karet', 'Karet'),
  ('RHJ R 6" WO bushing + cover)', 'RHAJA — karet', 'Karet'),
  ('RHJ R 8" H', 'RHAJA — karet', 'Karet'),
  ('RHJ R 8" M', 'RHAJA — karet', 'Karet'),
  ('RHJ R 8" R', 'RHAJA — karet', 'Karet'),
  ('RHJ R 8" WO', 'RHAJA — karet', 'Karet'),
  ('ROLLER PHINOLIQ 1"', 'Light duty nylon 1" (ERH-06)', 'Nylon')
)
update public.products p
   set kelompok = 'RHAJA Series',
       bahan    = coalesce(p.bahan, m.bahan)
  from peta m
 where lower(p.kode) = lower(m.kode)
   and (p.kelompok = m.kel_lama                                    -- belum dipindah (PROD)
        or (p.kelompok = 'RHAJA Series' and p.bahan is null and m.bahan is not null));   -- sudah dipindah (DEV): isi bahan saja
