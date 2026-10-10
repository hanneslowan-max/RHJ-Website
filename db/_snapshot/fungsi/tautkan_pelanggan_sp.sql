CREATE OR REPLACE FUNCTION public.tautkan_pelanggan_sp(p_so bigint, p_customer bigint, p_industri text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s       public.sales_orders;
  c       public.customers;
  v_ind   text := nullif(btrim(coalesce(p_industri, '')), '');
  v_k     text;
  v_hp    text;
  v_po    bigint;
  v_sales text;
  v_pakai boolean := true;
begin
  if not public.setara_owner() then
    raise exception 'Hanya owner/GM yang menautkan SP ke pelanggan tertentu.' using errcode = '42501';
  end if;
  if v_ind is not null and v_ind not in ('Otomotif','Non Otomotif','Bengkel Otomotif') then
    raise exception 'Kategori industri hanya Otomotif, Non Otomotif, atau Bengkel Otomotif.' using errcode = '22023';
  end if;
  select * into s from public.sales_orders where id = p_so for update;
  if s.id is null then raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode = 'P0002'; end if;
  if s.batal then raise exception 'Surat Pesanan % sudah dibatalkan.', s.no_sp using errcode = '22023'; end if;
  if s.customer_id is not null then
    raise exception 'Surat Pesanan % sudah tertaut ke data pelanggan "%".', s.no_sp,
      (select x.nama from public.customers x where x.id = s.customer_id) using errcode = 'P0001';
  end if;
  select * into c from public.customers where id = p_customer;
  if c.id is null then raise exception 'Pelanggan #% tidak ditemukan.', p_customer using errcode = 'P0002'; end if;
  if c.blacklist then
    raise exception 'Pelanggan "%" masuk daftar hitam — SP tidak ditautkan ke pelanggan daftar hitam.', c.nama
      using errcode = '22023';
  end if;
  if public.sp_pelanggan_hitam(c.id, null, null, null) is not null then   -- 139s: kembaran pelanggan daftar hitam
    raise exception 'Pelanggan "%" cocok nama/No. HP dengan pelanggan yang masuk daftar hitam — SP tetap akan ditahan bila '
                    'ditautkan ke sana. Beri pembeda pada nama/No. HP pelanggannya di tab Pelanggan dulu.', c.nama
      using errcode = '22023';
  end if;
  v_k := public.kunci_nama_pelanggan(public.rhj_nama_rapi(s.kepada));
  v_hp := public.hp_baku(s.telp);
  if not ((char_length(coalesce(v_k, '')) >= 2
           and (public.kunci_nama_pelanggan(c.nama) = v_k
                or (c.nama_lama is not null and public.kunci_nama_pelanggan(c.nama_lama) = v_k)))
          or (v_hp is not null and c.hp = v_hp)) then
    raise exception 'Nama/No. HP Surat Pesanan % ("%") tidak cocok dengan pelanggan "%". Bila memang pelanggan itu, ubah '
                    'Kepada SP lewat Minta ubah SP dulu.', s.no_sp, coalesce(s.kepada, ''), c.nama
      using errcode = 'P0001';
  end if;
  if c.sales_rep_id is not null and s.sales_rep_id is not null and c.sales_rep_id <> s.sales_rep_id then
    select nama into v_sales from public.sales_reps where id = c.sales_rep_id;
    raise exception 'Pelanggan "%" dipegang sales %, bukan sales SP ini — bila memang pelanggan yang sama, pindahkan dulu '
                    'pelanggannya ke sales SP di tab Pelanggan.', c.nama, coalesce(v_sales, '#' || c.sales_rep_id)
      using errcode = 'P0001';
  end if;
  if s.po_id is not null then
    select p.customer_id into v_po from public.purchase_orders p where p.id = s.po_id;
    if v_po is not null and v_po <> c.id then
      raise exception 'PO Surat Pesanan % sudah atas nama pelanggan lain — pelanggan SP dan PO harus sama.', s.no_sp
        using errcode = 'P0001';
    end if;
  end if;

  update public.sales_orders set customer_id = c.id, diubah_pada = now(), diubah_oleh = auth.uid() where id = p_so;
  if s.po_id is not null then
    update public.purchase_orders set customer_id = c.id where id = s.po_id and customer_id is null;
  end if;
  if v_ind is not null then
    if c.industri is null then update public.customers set industri = v_ind where id = c.id;
    else v_pakai := c.industri = v_ind; end if;
  end if;
  return jsonb_build_object('customer_id', c.id, 'dibuat', false, 'dicocokkan', 'pilih', 'kategori_dipakai', v_pakai,
                            'industri', (select x.industri from public.customers x where x.id = c.id), 'nama', c.nama);
end $function$;
