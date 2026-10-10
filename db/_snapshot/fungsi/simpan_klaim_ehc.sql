CREATE OR REPLACE FUNCTION public.simpan_klaim_ehc(p_klaim bigint, p_data jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_peran text := public.peran_saya();
  v_hari  date := public.hari_ini_wib();
  k       public.ehc_klaim;
  v_baru  boolean := p_klaim is null;
  v_id    bigint;
  v_kep   text := lower(btrim(coalesce(p_data->>'keperluan', '')));
  v_cara  text := lower(btrim(coalesce(p_data->>'cara_bayar', '')));
  v_tgl   date;
  v_cust  bigint;
  v_pic   public.customer_pics;
  v_rek   public.sales_rep_rekening;
  v_ket   text := nullif(btrim(coalesce(p_data->>'keterangan', '')), '');
  v_alas  text := nullif(btrim(coalesce(p_data->>'cepat_alasan', '')), '');
  v_alok  jsonb := p_data->'alokasi';
  v_berk  jsonb := coalesce(p_data->'berkas', '[]'::jsonb);
  v_rep   bigint;
  v_utama bigint;
  v_total numeric(14,2) := 0;
  v_lintas boolean := false;
  v_n     integer;
  v_sisa  numeric;
  v_lama  numeric;
  v_cust_sp boolean := false;
  a       record;
  s       record;
  b       jsonb;
  v_path  text;
begin
  -- 1 · peran & bentuk data
  if not public.boleh_alur_jual() then
    raise exception 'Anda tidak berhak mengajukan atau mengubah klaim EHC.' using errcode = '42501';
  end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'Isi klaim tidak terbaca.' using errcode = '22023';
  end if;

  -- 2 · klaim lama (ubah, #61)
  if not v_baru then
    select * into k from public.ehc_klaim where id = p_klaim for update;
    if not found then raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002'; end if;
    if not (public.klaim_ehc_saya(p_klaim) or v_peran in ('owner','gm','staff')) then
      raise exception 'Klaim EHC ini bukan milik Anda.' using errcode = '42501';
    end if;
    if k.status <> 'diajukan' then
      raise exception 'Klaim EHC ini berstatus %, tidak bisa diubah lagi.', k.status using errcode = '22023';
    end if;
    if k.transfer_batch_id is not null then
      raise exception 'Klaim EHC ini sudah ditransfer (batch #%).', k.transfer_batch_id using errcode = '22023';
    end if;
    if public.klaim_ehc_terkunci_pengajuan(p_klaim) is not null then
      raise exception 'Klaim EHC ini sudah masuk pengajuan transfer, tidak bisa diubah.' using errcode = '22023';
    end if;
    if k.cepat_minta and k.cepat_ok is distinct from false then
      raise exception 'Klaim ini sedang/sudah diajukan sebagai EHC cepat. Tarik permintaan cepatnya dulu '
                      'kalau masih menunggu GM.' using errcode = '22023';
    end if;
    if v_hari > public.cutoff_ehc(k.periode) then
      raise exception 'Periode % sudah lewat cutoff (%). Klaim ini terkunci untuk diperiksa GM.',
                      k.periode, to_char(public.cutoff_ehc(k.periode), 'DD-MM-YYYY') using errcode = '22023';
    end if;
    if v_alas is not null then
      raise exception 'EHC cepat untuk klaim yang sudah ada diminta lewat tombol "Minta EHC cepat".'
        using errcode = '22023';
    end if;
  end if;

  -- 3 · untuk apa & cara bayar
  if v_kep not in ('uang_customer','entertain','bongkar_muat') then
    raise exception 'Pilih untuk apa EHC ini dipakai: transfer ke customer, entertain, atau bongkar muat.'
      using errcode = '22023';
  end if;
  if v_cara = 'kartu_kredit' then
    raise exception 'Pemakaian kartu kredit perusahaan dicatat lewat statement dari finance (menyusul), '
                    'bukan dari form ini.' using errcode = '22023';
  end if;
  if v_cara not in ('transfer','reimburse') then
    raise exception 'Pilih cara bayar: transfer langsung ke customer, atau sales bayar dulu (reimburse).'
      using errcode = '22023';
  end if;

  -- 4 · tanggal transaksi
  begin
    v_tgl := (p_data->>'tanggal')::date;
  exception when others then
    raise exception 'Tanggal transaksi tidak terbaca.' using errcode = '22023';
  end;
  if v_tgl is null then raise exception 'Tanggal transaksi wajib diisi.' using errcode = '22023'; end if;
  if v_tgl > v_hari then
    raise exception 'Tanggal transaksi tidak boleh di masa depan.' using errcode = '22023';
  end if;

  -- 5 · bentuk alokasi
  if jsonb_typeof(v_alok) is distinct from 'array' or jsonb_array_length(v_alok) = 0 then
    raise exception 'Pilih minimal satu SP yang saldo EHC-nya dipakai.' using errcode = '22023';
  end if;
  if jsonb_array_length(v_alok) > 20 then
    raise exception 'Satu klaim paling banyak memakai 20 SP.' using errcode = '22023';
  end if;
  begin
    perform 1 from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric);
  exception when others then
    raise exception 'Daftar SP dan nominal tidak terbaca.' using errcode = '22023';
  end;
  if exists (select 1 from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric)
              where x.so_id is null or x.nominal is null) then
    raise exception 'Setiap SP wajib punya nominal.' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric)
              where x.nominal <= 0 or x.nominal <> trunc(x.nominal, 2)) then
    raise exception 'Nominal per SP harus lebih dari nol dan paling banyak dua angka di belakang koma (sen).'
      using errcode = '22023';
  end if;
  if (select count(*) from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric))
     <> (select count(distinct x.so_id) from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric)) then
    raise exception 'SP yang sama dipilih dua kali.' using errcode = '22023';
  end if;

  -- 6 · kepemilikan SP dulu (pesan tanpa nomor SP orang lain), baru dikunci
  for a in select x.so_id from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric) loop
    if not public.boleh_lihat_sp(a.so_id) then
      raise exception 'Ada SP yang bukan milik Anda. Saldo EHC hanya bisa dipakai dari SP yang Anda pegang.'
        using errcode = '42501';
    end if;
  end loop;
  -- kunci SP (urut id) supaya dua klaim bersamaan tidak sama-sama lolos cek saldo
  perform 1 from public.sales_orders
   where id in (select x.so_id from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric))
   order by id for update;

  begin
    v_cust := (p_data->>'customer_id')::bigint;
  exception when others then v_cust := null; end;

  for a in select (e.v->>'so_id')::bigint as so_id, (e.v->>'nominal')::numeric as nominal, e.ord
             from jsonb_array_elements(v_alok) with ordinality as e(v, ord)
            order by e.ord loop
    select so.id, so.no_sp, so.batal, so.sales_rep_id, so.customer_id
      into s from public.sales_orders so where so.id = a.so_id;
    if not found then raise exception 'SP #% tidak ditemukan.', a.so_id using errcode = 'P0002'; end if;
    if s.batal then raise exception 'SP % sudah dibatalkan.', s.no_sp using errcode = '22023'; end if;
    if s.sales_rep_id is null then
      raise exception 'SP % belum punya sales.', s.no_sp using errcode = '22023';
    end if;
    if s.customer_id is null then
      raise exception 'SP % belum ditautkan ke data pelanggan. Minta Vonny/GM melengkapi pelanggan SP itu dulu.',
                      s.no_sp using errcode = '22023';
    end if;
    -- pemilik klaim: dari SP saat klaim dibuat; beku sesudahnya
    if v_rep is null then
      v_rep := case when v_baru then s.sales_rep_id else k.sales_rep_id end;
      v_utama := s.id;
    end if;
    if s.sales_rep_id <> v_rep then
      raise exception 'Semua SP dalam satu klaim EHC harus milik sales yang sama dengan pemilik klaim.'
        using errcode = '22023';
    end if;
    -- saldo yang dipakai klaim ini sebelumnya (ubah)
    v_lama := coalesce((select x.nominal from public.ehc_klaim_alokasi x
                         where x.klaim_id = p_klaim and x.so_id = a.so_id), 0);
    if exists (select 1 from public.komisi_klaim kk where kk.so_id = a.so_id) and a.nominal > v_lama then
      raise exception 'Komisi SP % sudah diklaim — EHC-nya sudah tertutup dan sisanya masuk kas sales.', s.no_sp
        using errcode = '22023';
    end if;
    select trunc(coalesce(r.total_ehc, 0), 2)
           - coalesce((select sum(x.nominal) from public.ehc_klaim_alokasi x
                         join public.ehc_klaim kx on kx.id = x.klaim_id
                        where x.so_id = a.so_id and kx.status in ('diajukan','disetujui')
                          and kx.id is distinct from p_klaim), 0)
      into v_sisa
      from public.sales_orders so left join public.so_ringkas r on r.so_id = so.id
     where so.id = a.so_id;
    if a.nominal > coalesce(v_sisa, 0) then
      raise exception 'Saldo EHC SP % tinggal %, tidak cukup untuk %.',
                      s.no_sp, public.rp_teks(greatest(coalesce(v_sisa, 0), 0)), public.rp_teks(a.nominal)
        using errcode = '22023';
    end if;
    if s.customer_id = v_cust then v_cust_sp := true; end if;
    if s.customer_id is distinct from v_cust then v_lintas := true; end if;
    v_total := v_total + a.nominal;
  end loop;

  -- 7 · customer penerima: customer SP sendiri selalu boleh; customer lain harus
  --     milik sales itu atau belum bertuan (dan klaimnya jadi lintas → GM)
  if v_cust is null or not exists (select 1 from public.customers where id = v_cust) then
    raise exception 'Pilih customer penerima / yang di-entertain.' using errcode = '22023';
  end if;
  if not v_cust_sp and not public.pic_pelanggan_saya(v_cust) then
    raise exception 'Customer itu dipegang sales lain. EHC tidak bisa dipakai untuk pelanggan sales lain.'
      using errcode = '42501';
  end if;

  -- 8 · rekening tujuan
  if v_cara = 'transfer' then
    begin
      select * into v_pic from public.customer_pics where id = (p_data->>'pic_id')::bigint;
    exception when others then v_pic := null; end;
    if v_pic.id is null then
      raise exception 'Pilih PIC penerima transfer.' using errcode = '22023';
    end if;
    if v_pic.customer_id is distinct from v_cust then
      raise exception 'PIC % bukan PIC customer penerima.', v_pic.nama using errcode = '42501';
    end if;
    if not coalesce(v_pic.aktif, true) then
      raise exception 'PIC % sudah tidak aktif.', v_pic.nama using errcode = '22023';
    end if;
    if coalesce(btrim(v_pic.bank), '') = '' or coalesce(btrim(v_pic.no_rekening), '') = '' then
      raise exception 'PIC % belum punya rekening. Isi rekeningnya dulu.', v_pic.nama using errcode = '22023';
    end if;
    -- transfer "ke customer" yang ternyata ke rekening sales
    if exists (select 1 from public.sales_rep_rekening r
                where regexp_replace(r.no_rekening, '\D', '', 'g') = regexp_replace(v_pic.no_rekening, '\D', '', 'g')) then
      raise exception 'Rekening PIC % sama dengan rekening sales. Transfer ke customer harus ke rekening customer.',
                      v_pic.nama using errcode = '42501';
    end if;
  else
    -- reimburse: rekening sales pemilik klaim (diisi finance) disalin bila sudah ada
    select * into v_rek from public.sales_rep_rekening where sales_rep_id = v_rep;
  end if;

  -- 9 · lampiran
  if jsonb_typeof(v_berk) <> 'array' then
    raise exception 'Daftar lampiran tidak berbentuk daftar.' using errcode = '22023';
  end if;
  if jsonb_array_length(v_berk) > 10 then
    raise exception 'Paling banyak 10 lampiran sekali simpan.' using errcode = '22023';
  end if;
  for b in select * from jsonb_array_elements(v_berk) loop
    v_path := btrim(coalesce(b->>'path', ''));
    if coalesce(btrim(b->>'nama_berkas'), '') = '' or v_path = '' then
      raise exception 'Ada lampiran yang tidak punya nama berkas atau alamat penyimpanan.' using errcode = '22023';
    end if;
    if v_path not like 'ehc/%' then
      raise exception 'Lampiran % tidak berada di folder bukti EHC.', b->>'nama_berkas' using errcode = '42501';
    end if;
    if not exists (select 1 from storage.objects o
                    where o.bucket_id = 'dokumen' and o.name = v_path
                      and (o.owner = auth.uid() or o.owner_id = auth.uid()::text)) then
      raise exception 'Lampiran % tidak ditemukan atau bukan unggahan Anda. Unggah ulang berkasnya.',
                      b->>'nama_berkas' using errcode = '42501';
    end if;
    if exists (select 1 from public.ehc_klaim_berkas f where f.path = v_path) then
      raise exception 'Lampiran % sudah dipakai klaim lain.', b->>'nama_berkas' using errcode = '22023';
    end if;
  end loop;
  if v_baru and jsonb_typeof(p_data->'berkas_hapus') = 'array' and jsonb_array_length(p_data->'berkas_hapus') > 0 then
    raise exception 'Klaim baru tidak punya lampiran untuk dibuang.' using errcode = '22023';
  end if;

  -- 10 · simpan
  if v_baru then
    perform set_config('rhj.klaim_ehc', 'on', true);
    insert into public.ehc_klaim (so_id, pic_id, bank, no_rekening, atas_nama, dini, tanggal, cara_bayar,
                                  keperluan, customer_id, keterangan, periode, status, lintas_customer,
                                  sales_rep_id)
    values (v_utama,
            case when v_cara = 'transfer' then v_pic.id end,
            case when v_cara = 'transfer' then v_pic.bank        else v_rek.bank end,
            case when v_cara = 'transfer' then v_pic.no_rekening else v_rek.no_rekening end,
            case when v_cara = 'transfer' then v_pic.atas_nama   else v_rek.atas_nama end,
            false, v_tgl, v_cara, v_kep, v_cust, v_ket, public.periode_ehc(v_hari), 'diajukan', v_lintas,
            v_rep)
    returning id into v_id;
    perform set_config('rhj.klaim_ehc', 'off', true);
    insert into public.ehc_klaim_nilai (klaim_id, nominal, kas) values (v_id, v_total, 0);
  else
    v_id := p_klaim;
    insert into public.ehc_klaim_log (klaim_id, aksi, data, oleh)
    values (v_id, 'ubah',
            jsonb_build_object('klaim', to_jsonb(k),
              'nominal', (select n.nominal from public.ehc_klaim_nilai n where n.klaim_id = v_id),
              'alokasi', (select coalesce(jsonb_agg(jsonb_build_object('so_id', x.so_id, 'nominal', x.nominal)
                                                     order by x.id), '[]'::jsonb)
                            from public.ehc_klaim_alokasi x where x.klaim_id = v_id)),
            auth.uid());
    update public.ehc_klaim
       set so_id = v_utama,
           pic_id      = case when v_cara = 'transfer' then v_pic.id end,
           bank        = case when v_cara = 'transfer' then v_pic.bank        else v_rek.bank end,
           no_rekening = case when v_cara = 'transfer' then v_pic.no_rekening else v_rek.no_rekening end,
           atas_nama   = case when v_cara = 'transfer' then v_pic.atas_nama   else v_rek.atas_nama end,
           tanggal = v_tgl, cara_bayar = v_cara, keperluan = v_kep, customer_id = v_cust,
           keterangan = v_ket, lintas_customer = v_lintas,
           diubah_oleh = auth.uid(), diubah_pada = now()
     where id = v_id;
    update public.ehc_klaim_nilai set nominal = v_total, kas = 0 where klaim_id = v_id;
    -- SP yang tidak dipakai lagi: nominalnya 0 (barisnya tetap sebagai riwayat).
    update public.ehc_klaim_alokasi al set nominal = 0
     where al.klaim_id = v_id
       and al.so_id not in (select x.so_id from jsonb_to_recordset(v_alok) as x(so_id bigint, nominal numeric));
    if jsonb_typeof(p_data->'berkas_hapus') = 'array' then
      update public.ehc_klaim_berkas f
         set dibuang_pada = now(), dibuang_oleh = auth.uid()
       where f.klaim_id = v_id and f.dibuang_pada is null
         and f.id in (select x::bigint from jsonb_array_elements_text(p_data->'berkas_hapus') x);
    end if;
  end if;

  insert into public.ehc_klaim_alokasi (klaim_id, so_id, nominal)
  select v_id, (e.v->>'so_id')::bigint, (e.v->>'nominal')::numeric
    from jsonb_array_elements(v_alok) with ordinality as e(v, ord)
   order by e.ord
  on conflict (klaim_id, so_id) do update set nominal = excluded.nominal;

  insert into public.ehc_klaim_berkas (klaim_id, nama_berkas, path, ukuran, mime, dibuat_oleh)
  select v_id, btrim(x->>'nama_berkas'), btrim(x->>'path'),
         (select (o.metadata->>'size')::bigint from storage.objects o
           where o.bucket_id = 'dokumen' and o.name = btrim(x->>'path')),
         (select o.metadata->>'mimetype' from storage.objects o
           where o.bucket_id = 'dokumen' and o.name = btrim(x->>'path')),
         auth.uid()
    from jsonb_array_elements(v_berk) x;

  select count(*) into v_n from public.ehc_klaim_berkas where klaim_id = v_id and dibuang_pada is null;
  if v_n = 0 then
    raise exception 'Lampiran wajib: lampirkan bill/nota atau bukti transfer.' using errcode = '22023';
  end if;

  if v_baru then
    insert into public.ehc_klaim_log (klaim_id, aksi, oleh) values (v_id, 'ajukan', auth.uid());
    if v_alas is not null then
      perform public.minta_klaim_cepat(v_id, v_alas);
    end if;
  end if;
  return v_id;
end $function$;
