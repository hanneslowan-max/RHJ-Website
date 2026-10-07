-- ═══════════════════════════════════════════════════════════════════════
-- 122 · #50 lanjutan: No. HP wajib pada SP yang pelanggannya tidak dipilih dari data pelanggan
--
-- Keputusan Hannes (7 Okt): sales WAJIB mengisi No. HP di form SP bila pelanggannya tidak dipilih dari
-- data pelanggan (customer_id kosong) — supaya cek Vonny tidak lagi tertahan "No. HP kosong" (#50):
-- pelanggan baru yang dibuat saat cek Vonny wajib punya No. HP (buat_pelanggan_baru).
--
-- Aturannya (dijaga di sini, untuk SEMUA peran — owner/GM/staff juga, karena setiap SP tanpa pelanggan
-- master akhirnya butuh No. HP di cek Vonny):
--   · INSERT SP tanpa customer_id (mode tanpa PO / PO menyusul tanpa memilih pelanggan, atau dari PO lama
--     yang belum tertaut ke pelanggan) → telp wajib No. HP sah: sesudah dibakukan (hp_baku) 9–16 angka
--     dengan awalan bukan 0 — sama persis dengan syarat buat_pelanggan_baru;
--   · UPDATE: SP lama tanpa HP TIDAK dikunci. Hanya diperiksa bila No. HP-nya diubah (setelah dibakukan)
--     atau pelanggannya dilepas (customer_id terisi → kosong). Mengganti Kepada saja tidak diperiksa —
--     cek Vonny (berkas 120/121) yang menahan bila nama baru tidak cocok dengan data pelanggan, dan
--     tindakan "perbaiki nama Kepada" yang disarankannya tetap bisa dijalankan;
--   · SP batal tidak diperiksa.
-- telp tidak ditulis ulang: SP menyimpan nomor apa adanya; pembakuan hanya untuk memeriksa.
-- Nama trigger so_yy_*: trigger BEFORE berjalan urut abjad, jadi penolakan wewenang (so_jaga_sales,
-- so_pemilik, so_x_cash_only, so_y_hanya_gm) tetap muncul lebih dulu.
--
-- Tidak ada data yang diubah.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.jaga_hp_sp_tanpa_pelanggan()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_hp text;
begin
  if new.batal or new.customer_id is not null then return new; end if;
  if tg_op = 'UPDATE' and old.customer_id is null
     and public.hp_baku(new.telp) is not distinct from public.hp_baku(old.telp) then
    return new;   -- SP lama: No. HP tidak diubah → tidak diperiksa (yang kosong tetap boleh diubah hal lain)
  end if;
  v_hp := public.hp_baku(new.telp);
  if v_hp is null then
    if new.po_id is not null then
      raise exception 'No. HP pelanggan wajib diisi pada Surat Pesanan % karena PO-nya belum tertaut ke data pelanggan. Isi satu No. HP yang bisa dihubungi (mis. 0812xxxxxxx) — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek.',
        coalesce(new.no_sp, '(baru)') using errcode = '23502';
    end if;
    raise exception 'No. HP pelanggan wajib diisi pada Surat Pesanan % karena pelanggannya belum dipilih dari data pelanggan. Isi satu No. HP yang bisa dihubungi (mis. 0812xxxxxxx) — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek — atau pilih pelanggannya dari daftar.',
      coalesce(new.no_sp, '(baru)') using errcode = '23502';
  end if;
  if v_hp !~ '^[1-9][0-9]{8,15}$' then
    raise exception 'No. HP "%" pada Surat Pesanan % tidak valid — isi satu nomor, 9 sampai 16 angka, mis. 0812xxxxxxx.',
      new.telp, coalesce(new.no_sp, '(baru)') using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public.jaga_hp_sp_tanpa_pelanggan() from public, anon, authenticated;

create or replace trigger so_yy_hp_wajib
  before insert or update of customer_id, telp on public.sales_orders
  for each row execute function public.jaga_hp_sp_tanpa_pelanggan();
