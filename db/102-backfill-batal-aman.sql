-- Berkas 102 (#18, review G5 lensa keamanan-data): backfill qty_batal yang aman untuk DB yang sudah
--   menerima berkas 98 versi awal.
--
-- Temuan: backfill berkas 98 versi awal (`update … set qty_batal = qty where batal and qty_batal = 0`)
--   berjalan tanpa flag rhj.usul → sol_jaga_usul (jaga_baris_sp_terkunci) menolaknya karena saat migrasi
--   auth.uid() null (bukan owner/GM): "Baris Surat Pesanan … tidak bisa diubah langsung". Di DEV lolos
--   hanya karena baris batal = 0; di DB dengan baris batal lama berkas 98 gagal total.
--   Selain itu backfill itu membatalkan PENUH baris batal lama yang ternyata sudah terkirim sebagian
--   (bug lama (d)) → qty terkirim tidak tertagih & melanggar "qty efektif ≥ terkirim".
-- Perbaikan: berkas 98 sudah dikoreksi di tempat (bagian (2b)); berkas ini menjalankan backfill yang sama
--   (idempoten) untuk DB yang sudah menerima 98 versi awal: baris batal lama yang belum ter-backfill,
--   dan baris yang qty efektifnya < terkirim → qty_batal = qty − terkirim, catatan di batal_alasan.
-- Data: DEV 0 baris terdampak (tidak ada yang berubah). Tidak ada yang dihapus.
--
-- Cek sebelum rilis PROD (jalankan dulu, laporkan ke Hannes bila ada baris — SP berinvoice ikut berubah nilainya):
--   select s.no_sp, s.no_invoice, l.id, l.qty, l.qty_batal, l.batal,
--          (select coalesce(sum(kb.qty),0) from public.so_kirim_baris kb where kb.so_line_id = l.id) as terkirim
--     from public.sales_order_lines l join public.sales_orders s on s.id = l.so_id
--    where l.batal and exists (select 1 from public.so_kirim_baris kb where kb.so_line_id = l.id);

-- Backfill qty_batal dari penanda lama `batal` (turunan; bisa dipulihkan lewat catatan di batal_alasan).
--   * Sesudah trigger sol_qty_batal ada → penanda `batal` diturunkan ulang secara konsisten.
--   * rhj.usul = 'on'  : lewati sol_jaga_usul (saat migrasi auth.uid() null → bukan owner/GM).
--   * rhj.batal_baris  : jalur sah perubahan qty_batal/batal (sol_qty_batal).
--   * sol_vonny_gugur dimatikan sementara: backfill tidak mengubah isi SP, jadi cek Vonny yang sudah
--     disetujui tidak boleh gugur karenanya.
--   * Baris batal lama yang ternyata SUDAH terkirim sebagian (bug lama (d)): hanya sisa yang belum
--     terkirim yang dibatalkan (qty_batal = qty − terkirim) → qty terkirim kembali tertagih. Keadaan
--     lama dicatat di batal_alasan ("[migrasi] batal lama penuh …") agar bisa dipulihkan.
select set_config('rhj.usul', 'on', true);
select set_config('rhj.batal_baris', '1', true);
alter table public.sales_order_lines disable trigger sol_vonny_gugur;
with k as (
  select l.id, l.qty, coalesce((select sum(kb.qty) from public.so_kirim_baris kb where kb.so_line_id = l.id), 0) as kirim
    from public.sales_order_lines l
   where (l.batal and l.qty_batal = 0)                                                         -- belum di-backfill
      or (l.qty_batal > 0 and l.qty - l.qty_batal
          < coalesce((select sum(kb.qty) from public.so_kirim_baris kb where kb.so_line_id = l.id), 0)) -- backfill lama keliru
)
update public.sales_order_lines l
   set qty_batal    = greatest(k.qty - k.kirim, 0),
       batal_alasan = case when k.kirim > 0
                           then coalesce(l.batal_alasan || E'\n', '')
                                || '[migrasi] batal lama penuh ' || k.qty::text || '; terkirim ' || k.kirim::text
                                || ' → yang dibatalkan hanya sisa ' || greatest(k.qty - k.kirim, 0)::text
                           else l.batal_alasan end
  from k
 where l.id = k.id;
alter table public.sales_order_lines enable trigger sol_vonny_gugur;
select set_config('rhj.batal_baris', '', true);
select set_config('rhj.usul', '', true);
