CREATE OR REPLACE FUNCTION public.jaga_hp_sp_tanpa_pelanggan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_hp text; v_cek_hp boolean; v_cek_alamat boolean; v_alamat text;
begin
  if new.batal or new.customer_id is not null then return new; end if;
  v_alamat := regexp_replace(coalesce(new.alamat, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  if tg_op = 'INSERT' or old.batal or old.customer_id is not null then
    v_cek_hp := true; v_cek_alamat := true;
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
    if new.po_id is null and exists (select 1 from public.customers c where c.hp = v_hp) then
      raise exception 'No. HP % sudah terdaftar di data pelanggan — Surat Pesanan % tidak bisa memakai No. HP itu untuk pelanggan yang diketik sendiri. Pilih pelanggannya dari daftar pelanggan di form SP; bila tidak muncul di daftar Anda, hubungi owner/GM.',
        new.telp, coalesce(new.no_sp, '(baru)') using errcode = '23505';
    end if;
  end if;

  if v_cek_alamat and v_alamat = '' then
    if new.po_id is not null then
      raise exception 'Alamat pelanggan wajib diisi pada Surat Pesanan % karena PO-nya belum tertaut ke data pelanggan — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek.',
        coalesce(new.no_sp, '(baru)') using errcode = '23502';
    end if;
    raise exception 'Alamat pelanggan wajib diisi pada Surat Pesanan % karena pelanggannya belum dipilih dari data pelanggan — Vonny memakainya untuk mendaftarkan pelanggan ini saat cek. Atau pilih pelanggannya dari daftar.',
      coalesce(new.no_sp, '(baru)') using errcode = '23502';
  end if;
  return new;
end $function$;
