CREATE OR REPLACE FUNCTION public.jaga_daftar_hitam_sp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_c public.customers; v_link public.customers;
begin
  if auth.uid() is null then return new; end if;            -- migrasi / SQL Editor / service role
  if new.batal then return new; end if;
  if tg_op = 'UPDATE' and not (old.batal and not new.batal) then return new; end if;
  -- 139x (review 139s no. 1/10): SP yang dihidupkan lagi — baris sebelum dihidupkan juga diperiksa
  if tg_op = 'UPDATE' and not public.setara_owner()
     and public.sp_pelanggan_hitam(old.customer_id, old.po_id, old.kepada, old.telp) is not null then
    raise exception 'Surat Pesanan % tertahan daftar hitam — hanya owner/GM yang bisa menghidupkannya lagi.',
      coalesce(old.no_sp, '(baru)') using errcode = '23514';
  end if;
  select * into r from public.sp_pelanggan_hitam_rinci(new.customer_id, new.po_id, new.kepada, new.telp) limit 1;
  if r.id is null then return new; end if;
  -- 139s (review 139 no. 4): pelanggan/PO sales lain → biarkan RLS yang menolak (tanpa menyebut nama & alasannya)
  if public.peran_saya() = 'sales' and new.customer_id is not null and not public.pelanggan_saya(new.customer_id) then
    return new;
  end if;
  select * into v_c from public.customers where id = r.id;
  if r.cara = 'pelanggan' then
    if public.peran_saya() = 'sales' and not public.pic_pelanggan_saya(r.id) then
      raise exception 'Pelanggan SP ini masuk daftar hitam — Surat Pesanan tidak bisa dibuat. Hubungi owner/GM.'
        using errcode = '23514';
    end if;
    raise exception 'Pelanggan "%" masuk daftar hitam (%). Surat Pesanan tidak bisa dibuat atau dihidupkan lagi untuknya — '
                    'owner/GM mencabut daftar hitamnya dulu di tab Pelanggan bila memang boleh dilayani lagi.',
      v_c.nama, coalesce(v_c.alasan_blacklist, 'tanpa keterangan') using errcode = '23514';
  end if;
  if not public.setara_owner() then
    if r.cara = 'kembar' then
      select * into v_link from public.customers
       where id = coalesce(new.customer_id, (select p.customer_id from public.purchase_orders p where p.id = new.po_id));
      raise exception 'Pelanggan "%" cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa '
                      'dibuat. Bila ini perusahaan/orang lain, owner/GM memberi pembeda pada nama (mis. kota/cabang) atau '
                      'memperbaiki No. HP pelanggannya di tab Pelanggan.', v_link.nama using errcode = '23514';
    end if;
    raise exception 'Nama/No. HP "%" cocok dengan pelanggan yang masuk daftar hitam — Surat Pesanan tidak bisa dibuat. '
                    'Bila ini perusahaan/orang lain, beri pembeda pada namanya (mis. kota atau cabang), atau minta owner/GM.',
      coalesce(new.kepada, '') using errcode = '23514';
  end if;
  return new;   -- owner/GM: boleh dibuat; barangnya tetap ditahan sampai owner/GM membereskannya
end $function$;
