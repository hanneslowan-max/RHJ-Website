CREATE OR REPLACE FUNCTION public.tautkan_sales_dari_sheet(p_terapkan boolean DEFAULT false)
 RETURNS TABLE(putusan text, keterangan text, jumlah bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_batch bigint; v_pasang bigint := 0;
begin
  if not (public.peran_saya() in ('owner','gm','staff') or auth.uid() is null) then
    -- Sesi SQL Editor dikenali dari auth.uid() yang null, BUKAN dari peran
    -- di sana peran_saya() memang mengembalikan null. Yang ditolak
    -- adalah peran sungguhan yang tidak berwenang, bukan sesi tanpa login.
    raise exception 'Penautan sales dari sheet hanya untuk owner, GM, atau staff.'
      using errcode = '42501';
  end if;

  if p_terapkan then
    insert into public.tautan_sales_batch (oleh, catatan)
    values (auth.uid(), 'tautkan_sales_dari_sheet')
    returning id into v_batch;

    -- Hanya yang PERSIS cocok, hanya yang BELUM bertaut, dan hanya nama
    -- yang tidak mengandung pemisah. Ketiganya digabung di satu tempat
    -- supaya tidak ada jalan lain yang melewatkan salah satunya.
    with sasaran as (
      select c.id as customer_id, r.id as sales_rep_id
        from public.customers c
        join public.sales_reps r
          on public.norm_sales(r.nama) = public.norm_sales(c.salesman_teks)
       where c.sales_rep_id is null
         and public.norm_sales(c.salesman_teks) is not null
         -- Jaring kedua. Dengan pencocokan PERSIS, sel berisi dua nama
         -- memang tidak akan pernah cocok dengan satu pun nama di master,
         -- jadi baris ini sebetulnya tidak pernah menyala hari ini. Ia
         -- dibiarkan supaya niatnya terbaca di jalur yang menulis data,
         -- bukan cuma di view yang melaporkan.
         and btrim(c.salesman_teks) !~ '[,/&;]|\mdan\M'
         and (select count(*) from public.sales_reps r2
               where public.norm_sales(r2.nama) = public.norm_sales(c.salesman_teks)) = 1
    ),
    tulis as (
      update public.customers c
         set sales_rep_id = s.sales_rep_id
        from sasaran s
       where c.id = s.customer_id
      returning c.id, s.sales_rep_id
    )
    insert into public.tautan_sales_baris (batch_id, customer_id, sales_rep_id)
      select v_batch, t.id, t.sales_rep_id from tulis t;

    get diagnostics v_pasang = row_count;
    update public.tautan_sales_batch set jumlah = v_pasang where id = v_batch;
  end if;

  return query
  select t.putusan,
         t.nama_sheet || coalesce(' → ' || t.rep_nama, '')
           || case when t.rep_aktif is false then ' (nonaktif)' else '' end,
         t.belum_bertaut::bigint
    from public.tautan_sales_tinjau t
   order by 1, 3 desc;

  if p_terapkan then
    return query select 'DITERAPKAN'::text,
      ('batch #' || v_batch || ' — bisa dibatalkan dengan batalkan_tautan_sales('
        || v_batch || ')')::text,
      v_pasang;
  else
    return query select 'UJI COBA'::text,
      'Belum ada yang diubah. Jalankan tautkan_sales_dari_sheet(true) untuk menerapkan.'::text,
      0::bigint;
  end if;
end $function$;
