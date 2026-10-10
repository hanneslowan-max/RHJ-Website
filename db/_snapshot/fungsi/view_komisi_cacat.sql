CREATE OR REPLACE FUNCTION public.view_komisi_cacat(p_rel oid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare c record; v_inv boolean; v_kol text[]; v_harap text[];
begin
  select k.relkind, k.reloptions, k.relname into c from pg_class k where k.oid = p_rel;
  if c.relkind is null then return 'tidak ada'; end if;
  if c.relkind <> 'v' then return 'bukan view'; end if;
  select o.option_value::boolean into v_inv from pg_options_to_table(c.reloptions) o where o.option_name = 'security_invoker';
  if not coalesce(v_inv, false) then return 'tidak security_invoker'; end if;
  if exists (select 1 from pg_rewrite rw where rw.ev_class = p_rel and rw.rulename <> '_RETURN') then
    return 'ada rule selain _RETURN';
  end if;
  if not exists (select 1 from pg_rewrite rw
                   join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = rw.oid
                  where rw.ev_class = p_rel and rw.rulename = '_RETURN' and d.refclassid = 'pg_proc'::regclass
                    and d.refobjid = 'public.boleh_lihat_nilai_klaim()'::regprocedure) then
    return 'tanpa pemanggilan boleh_lihat_nilai_klaim()';
  end if;
  -- 139v: kolom dibekukan. Menambah/mengubah kolom view komisi = perbarui daftar ini DULU (berkas migrasi yang sama),
  -- sesudah memastikan kolom barunya tidak membuka angka komisi/persen bagi peran lain.
  v_harap := case c.relname
    when 'so_ringkas' then array['so_id','no_sp','tanggal','sales_rep_id','ppn_kena','status','total_barang','total_ehc',
      'sub_total','ppn','grand_total','komisi','ada_bawah_list','jumlah_baris','total_biaya','dasar_ppn','n_bawah_list',
      'n_tanpa_list','mode_ppn']
    when 'so_baris_hitung' then array['id','so_id','urut','product_id','qty','harga_nett','ehc_item','harga_list',
      'nilai_barang','nilai_ehc','nilai_baris','hammer','pct','jenis','harga_khusus_id','qty_pesan','qty_batal','mode_ppn',
      'nett_dpp','nilai_barang_dpp','nilai_ehc_dpp','nilai_baris_dpp','pct_berlaku','sumber_pct','perlu_gm']
    when 'cash_belum_cocok' then array['so_id','no_sp','tanggal','kepada','sales_rep_id','lunas','tgl_lunas','no_invoice',
      'total_barang','komisi_sekarang','komisi_kalau_cash']
    when 'komisi_belum_klaim' then array['so_id','no_sp','tanggal','kepada','customer_id','sales_rep_id','lunas',
      'tgl_lunas','telat','gm_pct','harga_ok','ada_bawah_list','total_barang','komisi','bisa_klaim','alasan']
  end;
  if v_harap is not null then
    select array_agg(a.attname::text order by a.attnum) into v_kol
      from pg_attribute a where a.attrelid = p_rel and a.attnum > 0 and not a.attisdropped;
    if v_kol is distinct from v_harap then
      return 'daftar kolom berubah — tinjau kolom barunya lalu perbarui daftar di public.view_komisi_cacat (berkas 139y)';
    end if;
  end if;
  return null;
end $function$;
