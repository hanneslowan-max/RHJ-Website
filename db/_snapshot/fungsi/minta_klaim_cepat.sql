CREATE OR REPLACE FUNCTION public.minta_klaim_cepat(p_klaim bigint, p_alasan text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.ehc_klaim; v_alasan text; v_pj bigint; v_sp text;
begin
  v_alasan := nullif(btrim(coalesce(p_alasan, '')), '');

  select * into k from public.ehc_klaim where id = p_klaim for update;
  if not found then
    raise exception 'Klaim EHC #% tidak ada.', p_klaim using errcode = 'P0002';
  end if;
  if not public.boleh_minta_klaim_cepat(p_klaim) then
    raise exception 'Anda tidak berhak mengajukan pencairan cepat untuk klaim ini.'
      using errcode = '42501';
  end if;
  if k.status = 'disetujui' then
    raise exception 'Klaim EHC ini sudah DISETUJUI GM — yang ditunggu sekarang daftar bayar finance, '
                    'tidak perlu dipercepat.' using errcode = '22023';
  end if;
  if k.status <> 'diajukan' then
    raise exception 'Klaim EHC ini berstatus % — hanya klaim yang masih diajukan yang bisa dipercepat.',
                    k.status using errcode = '22023';
  end if;
  if not exists (select 1 from public.ehc_klaim_berkas f where f.klaim_id = p_klaim and f.dibuang_pada is null) then
    raise exception 'Klaim ini belum punya lampiran. Ubah klaimnya dan lampirkan bukti dulu.' using errcode = '22023';
  end if;
  if k.cara_bayar = 'transfer' and coalesce(btrim(k.no_rekening), '') = '' then
    raise exception 'Klaim ini belum punya rekening tujuan.' using errcode = '22023';
  end if;
  if k.cara_bayar = 'reimburse'
     and not exists (select 1 from public.sales_rep_rekening r where r.sales_rep_id = k.sales_rep_id) then
    raise exception 'Klaim ini belum punya rekening tujuan (rekening sales belum diisi finance).' using errcode = '22023';
  end if;

  if v_alasan is null then
    raise exception 'Alasan mendesak wajib diisi — GM tidak bisa memutuskan pencairan di '
                    'luar jadwal tanpa tahu apa yang mendesak.' using errcode = '22023';
  end if;
  if length(v_alasan) < 10 then
    raise exception 'Alasan mendesak terlalu pendek (% huruf). Tulis apa yang mendesak dan '
                    'kapan uangnya dibutuhkan — GM memutuskan dari kalimat ini.',
                    length(v_alasan) using errcode = '22023';
  end if;

  if k.transfer_batch_id is not null then
    raise exception 'Klaim ini sudah ditransfer lewat batch #% — tidak ada yang perlu '
                    'dipercepat lagi.', k.transfer_batch_id using errcode = '22023';
  end if;
  if k.cepat_minta and k.cepat_ok is null then
    raise exception 'Klaim ini sudah diajukan sebagai klaim cepat dan masih menunggu GM. '
                    'Tarik dulu kalau alasannya mau diperbaiki.' using errcode = '22023';
  end if;

  v_pj := public.klaim_ehc_terkunci_pengajuan(p_klaim);
  if v_pj is not null then
    raise exception
      'Klaim ini sudah terkunci di pengajuan transfer bulanan #% yang belum selesai. '
      'Finance menarik dulu pengajuan itu (tarik_pengajuan_transfer), baru klaim ini '
      'diajukan sebagai klaim cepat.', v_pj
      using errcode = '22023';
  end if;

  perform set_config('rhj.cepat', 'on', true);
  update public.ehc_klaim
     set cepat_minta = true, cepat_ok = null, cepat_alasan = v_alasan, cepat_catatan = null,
         cepat_diminta_oleh = auth.uid(), cepat_diminta_pada = now(),
         cepat_diputus_oleh = null, cepat_diputus_pada = null
   where id = p_klaim;
  perform set_config('rhj.cepat', 'off', true);

  insert into public.ehc_cepat_log (klaim_id, aksi, alasan, oleh)
  values (p_klaim, 'minta', v_alasan, auth.uid());

  select no_sp into v_sp from public.sales_orders where id = k.so_id;
  return 'Klaim EHC ' || coalesce(v_sp, '#' || p_klaim) || ' diajukan sebagai EHC CEPAT dan '
      || 'masuk antrean GM. Selama menunggu, klaim ini tidak ikut pemeriksaan bulanan GM.';
end $function$;
