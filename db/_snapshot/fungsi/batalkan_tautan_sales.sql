CREATE OR REPLACE FUNCTION public.batalkan_tautan_sales(p_batch bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_balik bigint; v_lewat bigint;
begin
  if not (public.peran_saya() in ('owner','gm','staff') or auth.uid() is null) then
    raise exception 'Hanya owner, GM, atau staff yang boleh membatalkan penautan.'
      using errcode = '42501';
  end if;
  if not exists (select 1 from public.tautan_sales_batch where id = p_batch) then
    raise exception 'Batch #% tidak ada.', p_batch using errcode = 'P0002';
  end if;

  -- Yang dilewati dihitung LEBIH DULU. Menghitungnya sesudah update akan
  -- menghitung baris yang baru saja kita kosongkan sendiri — angkanya
  -- jadi sama besar dengan yang berhasil dikembalikan, dan laporan yang
  -- angkanya jelas-jelas salah membuat seluruh laporannya tidak dipercaya.
  select count(*) into v_lewat
    from public.tautan_sales_baris b
    join public.customers c on c.id = b.customer_id
   where b.batch_id = p_batch and c.sales_rep_id is distinct from b.sales_rep_id;

  -- Yang dikembalikan HANYA baris yang nilainya masih seperti yang kita
  -- pasang. Kalau sesudah itu ada orang yang memindahkannya ke sales lain,
  -- keputusan orang itu tidak boleh dihapus oleh pembatalan mesin.
  with balik as (
    update public.customers c
       set sales_rep_id = null
      from public.tautan_sales_baris b
     where b.batch_id = p_batch
       and c.id = b.customer_id
       and c.sales_rep_id = b.sales_rep_id
    returning c.id
  )
  select count(*) into v_balik from balik;

  delete from public.tautan_sales_baris where batch_id = p_batch;
  delete from public.tautan_sales_batch where id = p_batch;

  return 'Batch #' || p_batch || ' dibatalkan: ' || v_balik || ' pelanggan dikembalikan ke '
         || 'tanpa sales'
         || case when v_lewat > 0 then ', ' || v_lewat || ' dilewati karena sudah diubah orang '
                                             || 'sesudah penautan' else '' end || '.';
end $function$;
