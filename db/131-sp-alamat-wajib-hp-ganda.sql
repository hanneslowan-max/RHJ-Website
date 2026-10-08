-- ═══════════════════════════════════════════════════════════════════════
-- 131 · #50 lanjutan (keputusan Hannes 7 Okt): SP yang pelanggannya tidak dipilih dari data pelanggan
--       (1) wajib ALAMAT, (2) No. HP yang sudah dipakai pelanggan di data pelanggan DITOLAK
--
-- Melanjutkan berkas 122/124 (No. HP wajib, satu fungsi jaga_hp_sp_tanpa_pelanggan, trigger so_yy_hp_wajib):
--   (1) Alamat wajib (tidak kosong) sejak SP dibuat — semua peran, sama dengan No. HP. Cek Vonny membuat pelanggan
--       baru dengan alamat SP (buat_pelanggan_baru wajib alamat), jadi tanpa alamat SP tertahan "alamat kosong".
--   (2) No. HP (sesudah dibakukan) yang sudah tercatat sebagai No. HP pelanggan di data pelanggan → SP ditolak;
--       pesannya TIDAK menyebut nama pelanggan / sales pemegangnya, hanya meminta memilih pelanggannya dari daftar
--       (bila tidak muncul di daftar sales itu, owner/GM yang membereskan). Hanya untuk SP TANPA PO (mode tanpa PO /
--       PO menyusul — di situ form SP punya daftar pelanggan untuk dipilih). SP dari PO lama yang belum tertaut
--       pelanggan tidak bisa memilih pelanggan di form SP; penautannya tetap lewat cek Vonny (berkas 120/121 menahan
--       bila No. HP itu milik pelanggan sales lain).
--   Yang diperiksa (sama dengan 122/124): SP baru, SP batal yang dihidupkan lagi, dan SP yang pelanggannya dilepas
--   (customer_id terisi → kosong) — No. HP & alamat; selain itu hanya kolom yang DIUBAH (No. HP setelah dibakukan,
--   alamat setelah di-trim). SP lama yang alamatnya kosong / No. HP-nya ganda tetap bisa diubah hal lain.
--   Nama trigger tetap so_yy_hp_wajib (urutan sesudah penolakan wewenang); kolom pemicu ditambah alamat.
--
-- (3) RPC hp_terdaftar(p_hp) → boolean: form SP memeriksa No. HP SEBELUM nomor SP diambil (supaya nomornya tidak
--     hangus) dan memberi tahu saat mengetik. Hanya ya/tidak — tanpa nama pelanggan/sales. Hanya pembuat SP
--     (boleh_alur_jual).
--
-- (4) Hasil review adversarial (DEV: migrasi 131b):
--     · "Kosong" untuk alamat = hanya spasi/enter/tab (dulu btrim saja: alamat berisi enter lolos, dan alamat lama
--       berisi satu enter membuat persetujuan "Minta ubah SP" yang tidak menyentuh alamat gagal).
--     · No. HP "+62 (0)812…" / "62-0812…" dibakukan sama dengan "0812…" (hp_baku: awalan 620 → 62; dulu lolos dari
--       penolakan No. HP terdaftar dan cek Vonny bisa membuat pelanggan ganda). customers.hp ikut dibakukan saat
--       ditulis (trigger customers_hp_baku), sehingga indeks unik customers_hp_uniq menangkap bentuk lain nomor
--       yang sama dari jalur mana pun (buat_pelanggan_baru, REST).
--
-- Tidak ada data yang diubah. Tidak ada DROP.
-- ═══════════════════════════════════════════════════════════════════════

-- (4) bentuk lain nomor Indonesia "+62 (0)812…" → sama dengan "0812…"
create or replace function public.hp_baku(p_hp text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select case
    when x = '' then null
    when left(x, 3) = '620' then '62' || substr(x, 4)
    when left(x, 1) = '0' then '62' || substr(x, 2)
    when left(x, 1) = '8' then '62' || x
    else x end
  from (select regexp_replace(coalesce(p_hp, ''), '\D', '', 'g') as x) t
$$;

create or replace function public.bakukan_hp_pelanggan()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.hp is not null then new.hp := public.hp_baku(new.hp); end if;
  return new;
end $$;
revoke all on function public.bakukan_hp_pelanggan() from public, anon, authenticated;
create or replace trigger customers_hp_baku
  before insert or update of hp on public.customers
  for each row execute function public.bakukan_hp_pelanggan();

create or replace function public.jaga_hp_sp_tanpa_pelanggan()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_hp text; v_cek_hp boolean; v_cek_alamat boolean; v_alamat text;
begin
  if new.batal or new.customer_id is not null then return new; end if;
  -- (4) kosong = hanya spasi/enter/tab
  v_alamat := regexp_replace(coalesce(new.alamat, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  if tg_op = 'INSERT' or old.batal or old.customer_id is not null then
    v_cek_hp := true; v_cek_alamat := true;   -- SP baru / dihidupkan lagi / pelanggannya dilepas
  else
    v_cek_hp := public.hp_baku(new.telp) is distinct from public.hp_baku(old.telp);
    v_cek_alamat := v_alamat is distinct from
                    regexp_replace(coalesce(old.alamat, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  end if;

  if v_cek_hp then
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
    -- 131 (2): No. HP milik pelanggan di data pelanggan → pilih pelanggannya dari daftar (SP tanpa PO)
    if new.po_id is null and exists (select 1 from public.customers c where c.hp = v_hp) then
      raise exception 'No. HP % sudah terdaftar di data pelanggan — Surat Pesanan % tidak bisa memakai No. HP itu untuk pelanggan yang diketik sendiri. Pilih pelanggannya dari daftar pelanggan di form SP; bila tidak muncul di daftar Anda, hubungi owner/GM.',
        new.telp, coalesce(new.no_sp, '(baru)') using errcode = '23505';
    end if;
  end if;

  -- 131 (1): alamat wajib
  if v_cek_alamat and v_alamat = '' then
    if new.po_id is not null then
      raise exception 'Alamat pelanggan wajib diisi pada Surat Pesanan % karena PO-nya belum tertaut ke data pelanggan — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek.',
        coalesce(new.no_sp, '(baru)') using errcode = '23502';
    end if;
    raise exception 'Alamat pelanggan wajib diisi pada Surat Pesanan % karena pelanggannya belum dipilih dari data pelanggan — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek. Atau pilih pelanggannya dari daftar.',
      coalesce(new.no_sp, '(baru)') using errcode = '23502';
  end if;
  return new;
end $$;
revoke all on function public.jaga_hp_sp_tanpa_pelanggan() from public, anon, authenticated;

create or replace trigger so_yy_hp_wajib
  before insert or update of customer_id, telp, batal, alamat on public.sales_orders
  for each row execute function public.jaga_hp_sp_tanpa_pelanggan();

-- (3) pemeriksaan untuk form SP: ya/tidak saja
create or replace function public.hp_terdaftar(p_hp text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_hp text := public.hp_baku(p_hp);
begin
  if auth.uid() is null or not public.boleh_alur_jual() then
    raise exception 'Pemeriksaan No. HP hanya untuk pembuat Surat Pesanan.' using errcode = '42501';
  end if;
  if v_hp is null or v_hp !~ '^[1-9][0-9]{8,15}$' then return false; end if;
  return exists (select 1 from public.customers c where c.hp = v_hp);
end $$;
revoke all on function public.hp_terdaftar(text) from public, anon;
grant execute on function public.hp_terdaftar(text) to authenticated;
