CREATE OR REPLACE FUNCTION public.customers_tolak_nama_ganda()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_peran text;
  v_lama  text[] := '{}';
  v_cek   text[];
  v_k     text;
  v_ada   record;
begin
  if auth.uid() is null then return new; end if;                                  -- migrasi / SQL Editor / service
  if coalesce(current_setting('rhj.lewati_rapi_nama', true), 'off') = 'on' then return new; end if;  -- rapikan/pulihkan
  v_peran := public.peran_saya();
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'Nomor data pelanggan tidak bisa diubah.' using errcode = '22023';
    end if;
    v_lama := array[public.kunci_nama_pelanggan(old.nama), public.kunci_nama_pelanggan(old.nama_lama)];
    -- (no. 9) ganti nama pelanggan bertransaksi / berharga khusus
    if v_peran not in ('owner','gm','staff')
       and (public.rhj_nama_sidik(new.nama) is distinct from public.rhj_nama_sidik(old.nama)
            or public.kunci_nama_pelanggan(new.nama) is distinct from public.kunci_nama_pelanggan(old.nama))
       and (exists (select 1 from public.sales_orders s where s.customer_id = old.id)
            or exists (select 1 from public.purchase_orders p where p.customer_id = old.id)
            or exists (select 1 from public.quotes q where q.customer_id = old.id)
            or exists (select 1 from public.harga_khusus h where h.customer_id = old.id)) then
      raise exception 'Nama pelanggan "%" sudah dipakai di SP/PO/penawaran/harga khusus — penggantian namanya hanya oleh '
                      'owner, GM, atau staff. Sales hanya bisa merapikan penulisannya (huruf besar-kecil, tanda baca, '
                      'letak PT/CV).', old.nama;
    end if;
  end if;
  -- 139r (review 138 no. 2): huruf non-Latin (mis. Kiril/Yunani yang mirip huruf biasa) — selain owner/GM/staff ditolak
  if coalesce(v_peran, '') not in ('owner','gm','staff') and (tg_op = 'INSERT' or new.nama is distinct from old.nama)
     and public.ada_huruf_non_latin(new.nama) then
    raise exception 'Nama pelanggan "%" memuat huruf atau simbol khusus di luar huruf Latin biasa (mis. huruf Kiril/Yunani atau simbol yang mirip huruf). Ketik '
                    'ulang namanya dengan huruf biasa; bila memang perlu, minta owner/GM/staff.', new.nama
      using errcode = 'P0001';
  end if;
  -- 139r (review 138 no. 1): 8a berlaku untuk semua peran selain owner/GM/staff (mis. Vonny lewat lengkapi_pelanggan_sp)
  if v_peran in ('owner','gm','staff') then return new; end if;   -- (no. 8a) owner/GM/staff: boleh, layar memberi peringatan

  -- (no. 8a) sales: kunci BARU saja
  select array_agg(distinct k order by k) into v_cek
    from unnest(array[public.kunci_nama_pelanggan(new.nama), public.kunci_nama_pelanggan(new.nama_lama)]) k
   where coalesce(k, '') <> '' and not (k = any (v_lama));
  if v_cek is null then return new; end if;
  foreach v_k in array v_cek loop   -- dua simpan bersamaan dengan kunci sama: yang kedua menunggu lalu ditolak
    perform pg_advisory_xact_lock(hashtextextended('customers.kunci_nama:' || v_k, 0));
  end loop;
  select c.nama, sr.nama as sales into v_ada
    from public.customers c left join public.sales_reps sr on sr.id = c.sales_rep_id
   where c.id <> new.id
     and (public.kunci_nama_pelanggan(c.nama) = any (v_cek)
          or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = any (v_cek)))
   order by c.id limit 1;
  if found then
    raise exception 'Pelanggan "%" sudah ada di data pelanggan (%). Pilih dari daftar pencarian — satu perusahaan satu '
                    'data pelanggan. Bila memang perusahaan/orang lain dengan nama sama, tambahkan pembeda pada namanya '
                    '(mis. kota atau cabang).',
      v_ada.nama, coalesce('dipegang sales ' || v_ada.sales, 'belum bertuan') using errcode = '23505';
  end if;
  return new;
end $function$;
