CREATE OR REPLACE FUNCTION public.batalkan_sp(p_so bigint, p_alasan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; p_id bigint := p_so;
begin
  if not public.boleh_alur_jual() then
    raise exception 'Peran Anda tidak boleh membatalkan Surat Pesanan.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_alasan), '') = '' then
    raise exception 'Alasan pembatalan wajib diisi.' using errcode = '22023';
  end if;
  select * into v from public.sales_orders where id = p_id;
  if v.id is null then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_id using errcode = 'P0002';
  end if;
  if public.peran_saya() = 'sales'
     and v.sales_rep_id is distinct from public.sales_rep_saya() then
    raise exception 'Surat Pesanan ini bukan milik Anda. Hanya sales yang '
                    'memegangnya, atau owner/GM/staff, yang boleh membatalkannya.'
      using errcode = '42501';
  end if;
  if v.batal then
    raise exception 'Surat Pesanan % sudah dibatalkan.', v.no_sp using errcode = '22023';
  end if;
  /* SP yang sudah lunas atau sudah berfaktur SENGAJA tetap boleh
     dibatalkan. Sempat saya larang di sini, dan itu salah: berkas 21 sudah
     memutuskan sebaliknya — "pembatalan punya jalannya sendiri, dan
     memaksanya lewat pemeriksaan ini akan membuat SP salah input tidak
     bisa ditutup". SP yang salah input bisa saja terlanjur ditandai lunas;
     kalau pembatalannya dilarang, tidak ada lagi jalan keluar dari layar
     mana pun.

     Yang menahan sekarang bukan larangan, tapi peringatan di layar:
     akibatnya disebutkan sebelum tombolnya ditekan, dan alasannya wajib
     dicatat. */

  update public.sales_orders
     set batal = true, alasan_batal = btrim(p_alasan),
         diubah_pada = now(), diubah_oleh = auth.uid()
   where id = p_id;

  return 'Surat Pesanan ' || v.no_sp || ' dibatalkan.';
end $function$;
