-- Berkas 95 (#22): cash-only Riksa (rep 8) & Michael (rep 7) ditegakkan pada INSERT DAN UPDATE.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 28 Sep 2026. Belum ke produksi (butuh berkas 68 dulu:
-- kolom sales_reps.komisi_flat_pct & cash_only).
--
-- Masalah (#22): cash hanya dipaksa saat INSERT (trigger so_cash_only BEFORE INSERT). Sesudahnya:
--   (1) sales pemilik bisa PATCH cash_minta=false (RLS so_ubah mengizinkan; jaga_cash_sp hanya
--       mengunci bila cash_ok sudah terisi) -> SP jadi tempo;
--   (2) finance menandai "Bukan cash — tempo biasa" (cocokkan_cash_sp(p_so, false)), dan Ichi/GM/owner
--       bisa PATCH cash_ok=false langsung;
--   (3) staff/GM/owner memindah sales_rep_id SP ke rep cash_only -> cash_minta tetap false;
--   (4) INSERT pun bocor: so_cash_only (urutan alfabetis) jalan SEBELUM so_pemilik, jadi SP yang
--       dikirim sales tanpa sales_rep_id baru diisi rep-nya sesudah pengecekan cash;
--   (5) jaga_cash_only bukan SECURITY DEFINER (Ichi/Lie Sian/Selfie tidak bisa membaca sales_reps ->
--       trigger melihat "bukan cash-only") dan masih EXECUTE untuk PUBLIC/anon.
--
-- Isi berkas (tanpa perubahan tabel/kolom/view; rep lain tidak tersentuh):
--   (1) jaga_cash_only(): SECURITY DEFINER. Untuk SP rep cash_only: tolak cash_ok=false (INSERT,
--       perubahan ke false, atau pindah rep dengan cash_ok=false), tolak cash_minta true->false
--       selama rep tetap, dan paksa cash_minta=true saat INSERT / pindah ke rep cash_only (diam-diam,
--       supaya index.html lama yang selalu mengirim cash_minta:false tetap jalan).
--   (2) Trigger so_cash_only diganti so_x_cash_only (BEFORE INSERT OR UPDATE OF sales_rep_id,
--       cash_minta, cash_ok): namanya membuatnya jalan SESUDAH so_pemilik (INSERT) & so_jaga_sales
--       (UPDATE, pesan izin "sales pemilik SP" muncul lebih dulu), sebelum so_z_telat. Karena UPDATE OF,
--       PATCH lain (surat jalan, lunas, Vonny, batal, dll.) tidak menyalakannya.
--   (3) cocokkan_cash_sp(p_so, p_cash): p_cash=false ditolak untuk SP rep cash_only (pesan jelas di
--       jalur RPC; penjaga sebenarnya tetap trigger di atas). ACL tidak berubah.
--   (4) RPC baru sales_rep_cash_only() -> bigint[] id rep cash_only, untuk FE (Ichi tidak bisa membaca
--       sales_reps). Hanya authenticated; pending/nonaktif mendapat array kosong.
--
-- Berlaku untuk semua peran termasuk owner (invariant). Jalan keluarnya: staff/GM/owner memindah SP ke
-- sales lain dulu. SP yang dipindah KELUAR dari rep cash_only tetap cash_minta=true (seperti dulu).
--
-- Data DEV: 6 SP rep 7/8 semuanya cash_minta=true, cash_ok=null -> tidak ada yang perlu dirapikan.
-- PROD (saat dirilis): cek dulu, JANGAN diubah otomatis, laporkan ke Hannes:
--   select s.id, s.no_sp, s.sales_rep_id, s.cash_minta, s.cash_ok
--     from sales_orders s join sales_reps r on r.id = s.sales_rep_id
--    where r.cash_only and (not s.cash_minta or s.cash_ok is false);
--
-- Membalik:
--   drop trigger so_x_cash_only on public.sales_orders;
--   create trigger so_cash_only before insert on public.sales_orders
--     for each row execute function public.jaga_cash_only();
--   drop function public.sales_rep_cash_only();
--   lalu pulihkan dua badan fungsi lama di bawah.
--
-- Badan lama jaga_cash_only() (SET search_path TO 'public', BUKAN security definer):
--   begin
--     if TG_OP = 'INSERT' and new.sales_rep_id is not null
--        and exists (select 1 from public.sales_reps r where r.id = new.sales_rep_id and r.cash_only)
--        and new.cash_minta is not true then
--       new.cash_minta := true;
--     end if;
--     return new;
--   end
-- Badan lama cocokkan_cash_sp(p_so bigint, p_cash boolean) (security definer, search_path public):
--   declare s public.sales_orders;
--   begin
--     if public.peran_saya() not in ('owner','gm','finance','ichi') then
--       raise exception 'Hanya finance, Ichi, GM, atau owner yang boleh mencocokkan penjualan cash.';
--     end if;
--     select * into s from public.sales_orders where id = p_so;
--     if not found then raise exception 'Surat Pesanan tidak ditemukan.'; end if;
--     if s.batal then raise exception 'SP % sudah dibatalkan.', s.no_sp; end if;
--     update public.sales_orders set cash_ok = p_cash where id = p_so;
--   end

create or replace function public.jaga_cash_only()
 returns trigger
 language plpgsql
 security definer
 set search_path = public
as $function$
declare v_cash boolean; v_nama text;
begin
  -- #22: hanya SP milik sales cash_only yang disentuh; rep lain lewat apa adanya.
  if new.sales_rep_id is null then return new; end if;
  select r.cash_only, r.nama into v_cash, v_nama
    from public.sales_reps r where r.id = new.sales_rep_id;
  if not coalesce(v_cash, false) then return new; end if;

  -- (a) "Bukan cash — tempo" ditolak dari jalur mana pun (RPC, PATCH, pindah sales).
  if new.cash_ok is false
     and (tg_op = 'INSERT'
          or old.cash_ok is distinct from false
          or old.sales_rep_id is distinct from new.sales_rep_id) then
    raise exception 'SP % dipegang % — sales khusus penjualan cash. SP ini tidak bisa dinyatakan "bukan cash / tempo". Kalau memang tempo, minta staff, GM, atau owner memindahkan SP ini ke sales lain dulu.',
      coalesce(new.no_sp, '(baru)'), v_nama using errcode = '23514';
  end if;

  -- (b) klaim cash dilepas pada SP yang sales-nya tetap → tolak dengan jelas.
  if tg_op = 'UPDATE' and old.cash_minta and new.cash_minta is not true
     and old.sales_rep_id is not distinct from new.sales_rep_id then
    raise exception 'SP % dipegang % — sales khusus penjualan cash. Pembayarannya tidak bisa diubah jadi tempo.',
      coalesce(new.no_sp, '(baru)'), v_nama using errcode = '23514';
  end if;

  -- (c) SP baru / baru dipindah ke sales cash_only → dipaksa cash (form lama yang mengirim false tetap lolos).
  new.cash_minta := true;
  return new;
end $function$;
revoke execute on function public.jaga_cash_only() from public, anon;

drop trigger if exists so_cash_only on public.sales_orders;
drop trigger if exists so_x_cash_only on public.sales_orders;
create trigger so_x_cash_only
  before insert or update of sales_rep_id, cash_minta, cash_ok on public.sales_orders
  for each row execute function public.jaga_cash_only();

create or replace function public.cocokkan_cash_sp(p_so bigint, p_cash boolean)
 returns void
 language plpgsql
 security definer
 set search_path = public
as $function$
declare s public.sales_orders; v_nama text;
begin
  if public.peran_saya() not in ('owner','gm','finance','ichi') then
    raise exception 'Hanya finance, Ichi, GM, atau owner yang boleh mencocokkan penjualan cash.';
  end if;
  select * into s from public.sales_orders where id = p_so;
  if not found then raise exception 'Surat Pesanan tidak ditemukan.'; end if;
  if s.batal then raise exception 'SP % sudah dibatalkan.', s.no_sp; end if;
  -- #22: SP sales cash_only tidak punya jalur "bukan cash — tempo".
  if p_cash is false then
    select r.nama into v_nama from public.sales_reps r
     where r.id = s.sales_rep_id and r.cash_only;
    if found then
      raise exception 'SP % dipegang % — sales khusus penjualan cash, jadi tidak bisa dinyatakan "bukan cash / tempo". Biarkan "belum dicocokkan" sampai uang cash-nya diterima, atau minta staff/GM/owner memindahkan SP ke sales lain.',
        s.no_sp, v_nama using errcode = '23514';
    end if;
  end if;
  update public.sales_orders set cash_ok = p_cash where id = p_so;
end $function$;

create or replace function public.sales_rep_cash_only()
 returns bigint[]
 language sql
 stable
 security definer
 set search_path = public
as $function$
  select case when coalesce(public.peran_saya(), 'pending') in ('pending','nonaktif') then '{}'::bigint[]
              else coalesce(array_agg(r.id order by r.id), '{}'::bigint[]) end
    from public.sales_reps r
   where r.cash_only
$function$;
revoke execute on function public.sales_rep_cash_only() from public, anon;
grant execute on function public.sales_rep_cash_only() to authenticated;
