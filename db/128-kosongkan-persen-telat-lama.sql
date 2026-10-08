-- ═══════════════════════════════════════════════════════════════════════
-- 128 · data: kosongkan persen TELAT (sales_orders.gm_pct) yang tersisa dari keputusan HARGA sebelum berkas 124
--
-- Keputusan Hannes (8 Okt, no. 5 / catatan 18): sebelum berkas 124 persen GM untuk keputusan harga dan untuk invoice
-- telat >120 hari disimpan di kolom yang sama (gm_pct). Berkas 124 memisahkannya — persen harga kini di gm_pct_harga
-- (sudah disalin dari gm_pct untuk SP yang harganya disetujui) dan gm_pct KHUSUS persen telat. Tetapi SP lama masih
-- membawa gm_pct dari keputusan harga, sehingga bila invoicenya kelak telat: SP itu TIDAK masuk antrean telat
-- (antrean_gm: telat AND gm_pct IS NULL) dan persen harga dipakai untuk SELURUH SP (komisi_hitung: total × gm_pct).
--
-- Yang dilakukan: gm_pct dikosongkan pada SP yang BELUM telat dan BELUM diklaim komisinya. SP telat (persennya memang
-- keputusan telat) dan SP yang sudah diklaim (nominalnya sudah beku di komisi_klaim_nilai) tidak disentuh.
-- Untuk berjaga, persen harga yang belum tersalin (harga disetujui, gm_pct_harga kosong) disalin dulu — sama seperti
-- berkas 124 — supaya tidak ada persen harga yang hilang.
--
-- Angka: gm_pct hanya dibaca bila telat (komisi_hitung, antrean_gm, jaga_gerbang_komisi, komisi_belum_klaim) →
-- komisi, gerbang, dan antrean SP yang belum telat TIDAK bergeser (diuji: sidik so_ringkas, komisi_hitung,
-- komisi_belum_klaim, antrean_gm sama sebelum-sesudah). DEV: 8 SP (003, 007, 009, 010, 011, 015, 020, 032 -IX).
--
-- Kolom gm_pct dijaga jaga_kolom_sales (hanya GM/owner; migrasi tidak punya auth.uid()) → diubah dengan
-- SET LOCAL session_replication_role = replica selama pengubahan saja, dan setiap perubahan DICATAT sendiri di
-- audit_log (sebelum/sesudah, oleh_email 'migrasi 128'). Idempoten: jalan ulang tidak mengubah apa pun.
-- Tidak ada DROP.
-- ═══════════════════════════════════════════════════════════════════════

do $$
declare r record; n int := 0;
begin
  set local session_replication_role = replica;
  for r in
    select s.id, to_jsonb(s) as lama
      from public.sales_orders s
     where s.gm_pct is not null
       and s.telat is not true
       and not exists (select 1 from public.komisi_klaim k where k.so_id = s.id)
     order by s.id
       for update
  loop
    update public.sales_orders s
       set gm_pct_harga = case when s.harga_ok is true and s.gm_pct_harga is null then s.gm_pct else s.gm_pct_harga end,
           gm_pct = null
     where s.id = r.id;
    insert into public.audit_log (tabel, baris_id, aksi, oleh, oleh_email, pada, sebelum, sesudah)
    select 'sales_orders', r.id, 'UPDATE', null, 'migrasi 128 (persen telat lama dikosongkan)', now(), r.lama, to_jsonb(s2)
      from public.sales_orders s2 where s2.id = r.id;
    n := n + 1;
  end loop;
  set local session_replication_role = origin;
  raise notice '128: gm_pct dikosongkan pada % SP', n;
end $$;
