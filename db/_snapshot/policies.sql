-- SNAPSHOT RUJUKAN (read-only) — JANGAN dijalankan sebagai migrasi.
-- Sumber: Supabase DEV (eesdtbcualkdawhykchj), diambil 2026-10-10 dari pg_policies.
-- Isi: SEMUA policy RLS di skema public dan storage (150: public 136, storage 14),
--       urut skema, tabel, nama policy. USING / WITH CHECK apa adanya dari katalog.
-- Kebenaran tetap di DB live; snapshot ini bisa basi sesudah migrasi berikutnya.

create policy audit_owner on public.audit_log
  as permissive
  for select
  to public
  using (setara_owner());

create policy grup_baca on public.customer_groups
  as permissive
  for select
  to authenticated
  using (boleh_baca());

create policy cpic_baca on public.customer_pics
  as permissive
  for select
  to authenticated
  using ((boleh_baca() AND pic_pelanggan_saya(customer_id)));

create policy cpic_tulis on public.customer_pics
  as permissive
  for all
  to authenticated
  using ((boleh_alur_jual() AND pic_pelanggan_saya(customer_id)))
  with check ((boleh_alur_jual() AND pic_pelanggan_saya(customer_id)));

create policy cust_baca on public.customers
  as permissive
  for select
  to authenticated
  using ((( SELECT boleh_baca() AS boleh_baca) AND ((( SELECT peran_saya() AS peran_saya) <> 'sales'::text) OR (sales_rep_id IS NULL) OR (sales_rep_id = ( SELECT sales_rep_saya() AS sales_rep_saya)))));

create policy cust_hapus on public.customers
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy cust_tambah on public.customers
  as permissive
  for insert
  to public
  with check (boleh_ubah_crm());

create policy cust_ubah on public.customers
  as permissive
  for update
  to authenticated
  using ((( SELECT boleh_ubah_crm() AS boleh_ubah_crm) AND ((( SELECT peran_saya() AS peran_saya) <> 'sales'::text) OR (sales_rep_id IS NULL) OR (sales_rep_id = ( SELECT sales_rep_saya() AS sales_rep_saya)))))
  with check ((( SELECT boleh_ubah_crm() AS boleh_ubah_crm) AND ((( SELECT peran_saya() AS peran_saya) <> 'sales'::text) OR (sales_rep_id IS NULL) OR (sales_rep_id = ( SELECT sales_rep_saya() AS sales_rep_saya)))));

create policy dok_baca on public.documents
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_order_impor() OR ((peran_saya() = 'sales'::text) AND (jenis = 'Packing List'::text))));

create policy dok_hapus on public.documents
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy dok_tambah on public.documents
  as permissive
  for insert
  to public
  with check (boleh_alur_impor());

create policy dok_ubah on public.documents
  as permissive
  for update
  to public
  using (boleh_alur_impor())
  with check (boleh_alur_impor());

create policy massal_baca on public.edit_massal
  as permissive
  for select
  to public
  using (boleh_lihat_harga());

create policy massal_nilai_baca on public.edit_massal_nilai
  as permissive
  for select
  to public
  using (boleh_lihat_harga());

create policy ecl_baca on public.ehc_cepat_log
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id)));

create policy ehck_baca on public.ehc_klaim
  as permissive
  for select
  to public
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(id)));

create policy ehck_hapus on public.ehc_klaim
  as permissive
  for delete
  to public
  using (false);

create policy ehck_tambah on public.ehc_klaim
  as permissive
  for insert
  to public
  with check ((boleh_alur_jual() AND (COALESCE(current_setting('rhj.klaim_ehc'::text, true), 'off'::text) = 'on'::text)));

create policy ekal_baca on public.ehc_klaim_alokasi
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id)));

create policy ekb_baca on public.ehc_klaim_berkas
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id)));

create policy ekb_hapus on public.ehc_klaim_berkas
  as permissive
  for delete
  to public
  using (false);

create policy ekl_baca on public.ehc_klaim_log
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id)));

create policy ekn_baca on public.ehc_klaim_nilai
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id)));

create policy ekn_hapus on public.ehc_klaim_nilai
  as permissive
  for delete
  to public
  using (false);

create policy ekn_tambah on public.ehc_klaim_nilai
  as permissive
  for insert
  to public
  with check (false);

create policy ekn_ubah on public.ehc_klaim_nilai
  as permissive
  for update
  to public
  using (false)
  with check (false);

create policy ekp_baca on public.ehc_klaim_putusan
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_ehc_saya(klaim_id)));

create policy ekt_baca on public.ehc_klaim_tujuan
  as permissive
  for select
  to authenticated
  using (((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'finance'::text])) OR klaim_ehc_saya(klaim_id)));

create policy kp_baca on public.factory_codes
  as permissive
  for select
  to public
  using (boleh_lihat_order_impor());

create policy kp_hapus on public.factory_codes
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy kp_tambah on public.factory_codes
  as permissive
  for insert
  to public
  with check (boleh_ubah_impor());

create policy kp_ubah on public.factory_codes
  as permissive
  for update
  to public
  using (boleh_ubah_impor())
  with check (boleh_ubah_impor());

create policy hk_baca on public.harga_khusus
  as permissive
  for select
  to public
  using ((boleh_baca() AND pic_pelanggan_saya(customer_id)));

create policy hk_hapus on public.harga_khusus
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy hkl_baca on public.harga_khusus_log
  as permissive
  for select
  to public
  using ((boleh_baca() AND (EXISTS ( SELECT 1
   FROM harga_khusus h
  WHERE ((h.id = harga_khusus_log.harga_khusus_id) AND pic_pelanggan_saya(h.customer_id))))));

create policy baris_baca on public.import_lines
  as permissive
  for select
  to public
  using (boleh_lihat_order_impor());

create policy baris_hapus on public.import_lines
  as permissive
  for delete
  to public
  using (boleh_alur_impor());

create policy baris_tambah on public.import_lines
  as permissive
  for insert
  to public
  with check (boleh_alur_impor());

create policy baris_ubah on public.import_lines
  as permissive
  for update
  to public
  using (boleh_alur_impor())
  with check (boleh_alur_impor());

create policy komk_baca on public.komisi_klaim
  as permissive
  for select
  to public
  using ((boleh_lihat_nilai_klaim() OR ((peran_saya() = 'sales'::text) AND (sales_rep_saya() IS NOT NULL) AND ((sales_rep_id = sales_rep_saya()) OR (EXISTS ( SELECT 1
   FROM sales_orders s
  WHERE ((s.id = komisi_klaim.so_id) AND (s.sales_rep_id = sales_rep_saya()))))))));

create policy komk_hapus on public.komisi_klaim
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy komk_tambah on public.komisi_klaim
  as permissive
  for insert
  to public
  with check ((boleh_alur_jual() AND (COALESCE(current_setting('rhj.klaim_komisi'::text, true), 'off'::text) = 'on'::text)));

create policy kkb_baca on public.komisi_klaim_berkas
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_komisi_saya(klaim_id)));

create policy kkb_hapus on public.komisi_klaim_berkas
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy kkn_baca on public.komisi_klaim_nilai
  as permissive
  for select
  to authenticated
  using ((boleh_lihat_nilai_klaim() OR klaim_komisi_saya(klaim_id)));

create policy kkn_hapus on public.komisi_klaim_nilai
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy kkn_ubah on public.komisi_klaim_nilai
  as permissive
  for update
  to public
  using (boleh_lihat_hpp())
  with check (boleh_lihat_hpp());

create policy kkr_baca on public.komisi_klaim_rekening
  as permissive
  for select
  to public
  using (((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'finance'::text])) OR ((peran_saya() = 'sales'::text) AND (sales_rep_saya() IS NOT NULL) AND (sales_rep_id = sales_rep_saya()))));

create policy ev_baca on public.lead_events
  as permissive
  for select
  to public
  using ((EXISTS ( SELECT 1
   FROM leads l
  WHERE (l.id = lead_events.lead_id))));

create policy ev_tambah on public.lead_events
  as permissive
  for insert
  to public
  with check ((boleh_ubah_crm() AND (EXISTS ( SELECT 1
   FROM leads l
  WHERE (l.id = lead_events.lead_id)))));

create policy nilai_baca on public.lead_nilai
  as permissive
  for select
  to public
  using (boleh_lihat_hpp());

create policy nilai_tulis on public.lead_nilai
  as permissive
  for all
  to public
  using (boleh_ubah_hpp())
  with check (boleh_ubah_hpp());

create policy lead_baca on public.leads
  as permissive
  for select
  to public
  using ((( SELECT boleh_lihat_semua_lead() AS boleh_lihat_semua_lead) OR ((( SELECT peran_saya() AS peran_saya) = 'sales'::text) AND (sales_rep_id = ( SELECT sales_rep_saya() AS sales_rep_saya)))));

create policy lead_hapus on public.leads
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy lead_tambah on public.leads
  as permissive
  for insert
  to public
  with check ((boleh_ubah_crm() AND (boleh_lihat_semua_lead() OR (sales_rep_id = sales_rep_saya())) AND pelanggan_saya(customer_id)));

create policy lead_ubah on public.leads
  as permissive
  for update
  to public
  with check (((boleh_lihat_semua_lead() OR ((peran_saya() = 'sales'::text) AND (sales_rep_id = sales_rep_saya()))) AND pelanggan_saya(customer_id)));

create policy order_baca on public.orders
  as permissive
  for select
  to public
  using (boleh_lihat_order_impor());

create policy order_hapus on public.orders
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy order_tambah on public.orders
  as permissive
  for insert
  to public
  with check (setara_owner());

create policy order_ubah on public.orders
  as permissive
  for update
  to public
  using (boleh_alur_impor())
  with check (boleh_alur_impor());

create policy bayar_baca on public.payments
  as permissive
  for select
  to public
  using (boleh_lihat_impor());

create policy bayar_hapus on public.payments
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy bayar_tambah on public.payments
  as permissive
  for insert
  to public
  with check (boleh_ubah_bayar());

create policy bayar_ubah on public.payments
  as permissive
  for update
  to public
  using (boleh_ubah_bayar())
  with check (boleh_ubah_bayar());

create policy pru_baca on public.pic_rekening_ubah
  as permissive
  for select
  to public
  using (boleh_baca());

create policy pru_tambah on public.pic_rekening_ubah
  as permissive
  for insert
  to public
  with check (boleh_alur_jual());

create policy pru_ubah on public.pic_rekening_ubah
  as permissive
  for update
  to public
  using (boleh_approve())
  with check (boleh_approve());

create policy pol_baca on public.po_lines
  as permissive
  for select
  to public
  using ((EXISTS ( SELECT 1
   FROM purchase_orders p
  WHERE (p.id = po_lines.po_id))));

create policy pol_hapus on public.po_lines
  as permissive
  for delete
  to authenticated
  using (boleh_ubah_langsung());

create policy pol_tambah on public.po_lines
  as permissive
  for insert
  to authenticated
  with check (((EXISTS ( SELECT 1
   FROM purchase_orders p
  WHERE (p.id = po_lines.po_id))) AND boleh_input_po()));

create policy pol_ubah on public.po_lines
  as permissive
  for update
  to authenticated
  using (boleh_ubah_langsung());

create policy harga_baca on public.price_list
  as permissive
  for select
  to public
  using (( SELECT boleh_lihat_harga() AS boleh_lihat_harga));

create policy harga_hapus on public.price_list
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy harga_tambah on public.price_list
  as permissive
  for insert
  to public
  with check (setara_owner());

create policy harga_ubah on public.price_list
  as permissive
  for update
  to public
  using (setara_owner())
  with check (setara_owner());

create policy hpp_baca on public.product_costs
  as permissive
  for select
  to public
  using (boleh_lihat_hpp());

create policy hpp_hapus on public.product_costs
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy hpp_tambah on public.product_costs
  as permissive
  for insert
  to public
  with check (boleh_ubah_hpp());

create policy hpp_ubah on public.product_costs
  as permissive
  for update
  to public
  using (boleh_ubah_hpp())
  with check (boleh_ubah_hpp());

create policy psetc_baca on public.product_set_components
  as permissive
  for select
  to public
  using (boleh_lihat_produk());

create policy psetc_hapus on public.product_set_components
  as permissive
  for delete
  to public
  using (boleh_ubah_impor());

create policy psetc_tambah on public.product_set_components
  as permissive
  for insert
  to public
  with check (boleh_ubah_impor());

create policy psetc_ubah on public.product_set_components
  as permissive
  for update
  to public
  using (boleh_ubah_impor())
  with check (boleh_ubah_impor());

create policy pset_baca on public.product_sets
  as permissive
  for select
  to public
  using (boleh_lihat_produk());

create policy pset_hapus on public.product_sets
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy pset_tambah on public.product_sets
  as permissive
  for insert
  to public
  with check (boleh_ubah_impor());

create policy pset_ubah on public.product_sets
  as permissive
  for update
  to public
  using (boleh_ubah_impor())
  with check (boleh_ubah_impor());

create policy produk_baca on public.products
  as permissive
  for select
  to public
  using (( SELECT boleh_lihat_produk() AS boleh_lihat_produk));

create policy produk_hapus on public.products
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy produk_tambah on public.products
  as permissive
  for insert
  to public
  with check (boleh_ubah_produk());

create policy produk_ubah on public.products
  as permissive
  for update
  to public
  using (boleh_ubah_produk())
  with check (boleh_ubah_produk());

create policy profil_baca_sendiri on public.profiles
  as permissive
  for select
  to public
  using ((id = auth.uid()));

create policy profil_owner_baca on public.profiles
  as permissive
  for select
  to public
  using ((peran_saya() = 'owner'::text));

create policy profil_owner_ubah on public.profiles
  as permissive
  for update
  to public
  using ((peran_saya() = 'owner'::text))
  with check (((peran_saya() = 'owner'::text) AND ((id <> auth.uid()) OR (peran = 'owner'::text))));

create policy po_baca on public.purchase_orders
  as permissive
  for select
  to public
  using ((boleh_lihat_semua_jual() OR ((peran_saya() = 'sales'::text) AND (sales_rep_id = sales_rep_saya()))));

create policy po_hapus on public.purchase_orders
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy po_tambah on public.purchase_orders
  as permissive
  for insert
  to public
  with check ((boleh_input_po() AND pelanggan_saya(customer_id)));

create policy po_ubah on public.purchase_orders
  as permissive
  for update
  to public
  using (boleh_ubah_langsung())
  with check (pelanggan_saya(customer_id));

create policy ql_baca on public.quote_lines
  as permissive
  for select
  to authenticated
  using (boleh_lihat_quote(quote_id));

create policy ql_tulis on public.quote_lines
  as permissive
  for all
  to authenticated
  using (boleh_tulis_quote(quote_id))
  with check (boleh_tulis_quote(quote_id));

create policy quote_baca on public.quotes
  as permissive
  for select
  to authenticated
  using (((peran_saya() = 'vonny'::text) OR boleh_lihat_semua_lead() OR ((peran_saya() = 'sales'::text) AND (sales_rep_saya() IS NOT NULL) AND ((sales_rep_id = sales_rep_saya()) OR ((sales_rep_id IS NULL) AND (EXISTS ( SELECT 1
   FROM leads l
  WHERE ((l.id = quotes.lead_id) AND (l.sales_rep_id = sales_rep_saya())))))))));

create policy quote_tambah on public.quotes
  as permissive
  for insert
  to authenticated
  with check (((boleh_ubah_crm() OR (peran_saya() = 'vonny'::text)) AND pelanggan_saya(customer_id) AND ((peran_saya() <> 'sales'::text) OR (sales_rep_id = sales_rep_saya()))));

create policy quote_ubah on public.quotes
  as permissive
  for update
  to authenticated
  using ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'staff'::text, 'vonny'::text])))
  with check ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'staff'::text, 'vonny'::text])));

create policy sol_baca on public.sales_order_lines
  as permissive
  for select
  to public
  using ((EXISTS ( SELECT 1
   FROM sales_orders s
  WHERE (s.id = sales_order_lines.so_id))));

create policy sol_tulis on public.sales_order_lines
  as permissive
  for all
  to public
  using (((EXISTS ( SELECT 1
   FROM sales_orders s
  WHERE (s.id = sales_order_lines.so_id))) AND boleh_alur_jual()))
  with check (((EXISTS ( SELECT 1
   FROM sales_orders s
  WHERE (s.id = sales_order_lines.so_id))) AND boleh_alur_jual()));

create policy so_baca on public.sales_orders
  as permissive
  for select
  to public
  using ((((peran_saya() = 'sales'::text) AND (sales_rep_id = sales_rep_saya())) OR
CASE
    WHEN ((NOT batal) AND (no_surat_jalan IS NULL) AND (COALESCE(vonny_ok, false) = false)) THEN ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'vonny'::text])) OR ((dibuat_oleh = auth.uid()) AND boleh_alur_jual()))
    ELSE boleh_lihat_semua_jual()
END));

create policy so_hapus on public.sales_orders
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy so_tambah on public.sales_orders
  as permissive
  for insert
  to public
  with check ((boleh_alur_jual() AND pelanggan_saya(customer_id)));

create policy so_ubah on public.sales_orders
  as permissive
  for update
  to public
  using ((boleh_approve() OR boleh_terbitkan() OR boleh_pelunasan() OR (peran_saya() = 'staff'::text) OR ((peran_saya() = 'sales'::text) AND (sales_rep_id = sales_rep_saya()))))
  with check (pelanggan_saya(customer_id));

create policy srr_baca on public.sales_rep_rekening
  as permissive
  for select
  to public
  using (((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'finance'::text])) OR ((peran_saya() = 'sales'::text) AND (sales_rep_id = sales_rep_saya()))));

create policy srrl_baca on public.sales_rep_rekening_log
  as permissive
  for select
  to public
  using ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'finance'::text])));

create policy rep_baca on public.sales_reps
  as permissive
  for select
  to public
  using (boleh_baca());

create policy rep_tulis on public.sales_reps
  as permissive
  for all
  to public
  using (setara_owner())
  with check (setara_owner());

create policy sokirim_baca on public.so_kirim
  as permissive
  for select
  to public
  using ((EXISTS ( SELECT 1
   FROM sales_orders s
  WHERE (s.id = so_kirim.so_id))));

create policy sokirimb_baca on public.so_kirim_baris
  as permissive
  for select
  to public
  using ((EXISTS ( SELECT 1
   FROM so_kirim k
  WHERE (k.id = so_kirim_baris.kirim_id))));

create policy spc_baca on public.sp_counter
  as permissive
  for select
  to public
  using (boleh_baca());

create policy spek_sales_baca on public.spesifikasi_sales
  as permissive
  for select
  to authenticated
  using (((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'staff'::text, 'vonny'::text])) OR ((peran_saya() = 'sales'::text) AND (sales_rep_id = sales_rep_saya()))));

create policy sup_baca on public.suppliers
  as permissive
  for select
  to public
  using (boleh_lihat_order_impor());

create policy sup_ganti on public.suppliers
  as permissive
  for update
  to public
  using (setara_owner())
  with check (setara_owner());

create policy sup_hapus on public.suppliers
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy sup_tambah on public.suppliers
  as permissive
  for insert
  to public
  with check (setara_owner());

create policy log_baca on public.sync_log
  as permissive
  for select
  to public
  using (boleh_lihat_harga());

create policy log_tulis on public.sync_log
  as permissive
  for insert
  to public
  with check (setara_owner());

create policy sumber_baca on public.sync_sumber
  as permissive
  for select
  to public
  using (setara_owner());

create policy sumber_hapus on public.sync_sumber
  as permissive
  for delete
  to public
  using (boleh_hapus());

create policy sumber_tulis on public.sync_sumber
  as permissive
  for insert
  to public
  with check (setara_owner());

create policy sumber_ubah on public.sync_sumber
  as permissive
  for update
  to public
  using (setara_owner())
  with check (setara_owner());

create policy tsr_baca on public.tautan_sales_baris
  as permissive
  for select
  to authenticated
  using ((( SELECT peran_saya() AS peran_saya) = ANY (ARRAY['owner'::text, 'gm'::text, 'staff'::text])));

create policy tsb_baca on public.tautan_sales_batch
  as permissive
  for select
  to authenticated
  using ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text, 'staff'::text])));

create policy tb_baca on public.transfer_batch
  as permissive
  for select
  to authenticated
  using (boleh_lihat_nilai_klaim());

create policy tb_ubah on public.transfer_batch
  as permissive
  for update
  to authenticated
  using (boleh_rekap_transfer());

create policy tpj_baca on public.transfer_pengajuan
  as permissive
  for select
  to authenticated
  using (boleh_lihat_nilai_klaim());

create policy tpb_baca on public.transfer_pengajuan_baris
  as permissive
  for select
  to authenticated
  using (boleh_lihat_nilai_klaim());

create policy ubr_baca on public.ubah_sales_baris
  as permissive
  for select
  to authenticated
  using ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text])));

create policy ubb_baca on public.ubah_sales_batch
  as permissive
  for select
  to authenticated
  using ((peran_saya() = ANY (ARRAY['owner'::text, 'gm'::text])));

create policy uu_baca on public.usul_ubah
  as permissive
  for select
  to authenticated
  using ((setara_owner() OR ((jenis = 'po'::text) AND (EXISTS ( SELECT 1
   FROM purchase_orders p
  WHERE (p.id = usul_ubah.ref_id)))) OR ((jenis = 'sp'::text) AND (EXISTS ( SELECT 1
   FROM sales_orders s
  WHERE (s.id = usul_ubah.ref_id))))));

create policy dokumen_baca on storage.objects
  as permissive
  for select
  to public
  using (((bucket_id = 'dokumen'::text) AND boleh_lihat_impor() AND (name !~~ 'po/%'::text) AND (name !~~ 'ehc/%'::text) AND (name !~~ 'komisi/%'::text)));

create policy dokumen_hapus on storage.objects
  as permissive
  for delete
  to public
  using (((bucket_id = 'dokumen'::text) AND boleh_hapus()));

create policy dokumen_tulis on storage.objects
  as permissive
  for insert
  to public
  with check (((bucket_id = 'dokumen'::text) AND boleh_alur_impor() AND (name !~~ 'po/%'::text) AND (name !~~ 'ehc/%'::text) AND (name !~~ 'komisi/%'::text)));

create policy dokumen_ubah on storage.objects
  as permissive
  for update
  to public
  using (((bucket_id = 'dokumen'::text) AND boleh_alur_impor() AND (name !~~ 'po/%'::text) AND (name !~~ 'ehc/%'::text) AND (name !~~ 'komisi/%'::text)))
  with check (((bucket_id = 'dokumen'::text) AND boleh_alur_impor() AND (name !~~ 'po/%'::text) AND (name !~~ 'ehc/%'::text) AND (name !~~ 'komisi/%'::text)));

create policy rhj_ehc_bukti_baca on storage.objects
  as permissive
  for select
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (name ~~ 'ehc/%'::text) AND (EXISTS ( SELECT 1
   FROM ehc_klaim_berkas f
  WHERE ((f.path = objects.name) AND (boleh_lihat_nilai_klaim() OR klaim_ehc_saya(f.klaim_id)))))));

create policy rhj_ehc_bukti_hapus on storage.objects
  as permissive
  for delete
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (name ~~ 'ehc/%'::text) AND (owner = auth.uid()) AND (NOT (EXISTS ( SELECT 1
   FROM ehc_klaim_berkas f
  WHERE (f.path = objects.name))))));

create policy rhj_ehc_bukti_tulis on storage.objects
  as permissive
  for insert
  to authenticated
  with check (((bucket_id = 'dokumen'::text) AND (name ~~ 'ehc/%'::text) AND boleh_alur_jual()));

create policy rhj_komisi_bukti_baca on storage.objects
  as permissive
  for select
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (name ~~ 'komisi/%'::text) AND (EXISTS ( SELECT 1
   FROM komisi_klaim_berkas f
  WHERE ((f.path = objects.name) AND (boleh_lihat_nilai_klaim() OR klaim_komisi_saya(f.klaim_id)))))));

create policy rhj_komisi_bukti_hapus on storage.objects
  as permissive
  for delete
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (name ~~ 'komisi/%'::text) AND (owner = auth.uid()) AND (NOT (EXISTS ( SELECT 1
   FROM komisi_klaim_berkas f
  WHERE (f.path = objects.name))))));

create policy rhj_komisi_bukti_tulis on storage.objects
  as permissive
  for insert
  to authenticated
  with check (((bucket_id = 'dokumen'::text) AND (name ~~ 'komisi/%'::text) AND boleh_alur_jual()));

create policy rhj_packing_sales on storage.objects
  as permissive
  for select
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (peran_saya() = 'sales'::text) AND (EXISTS ( SELECT 1
   FROM documents d
  WHERE ((d.path = objects.name) AND (d.jenis = 'Packing List'::text))))));

create policy rhj_po_lampiran_baca on storage.objects
  as permissive
  for select
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (name ~~ 'po/%'::text) AND (EXISTS ( SELECT 1
   FROM purchase_orders p
  WHERE (p.lampiran = objects.name)))));

create policy rhj_po_lampiran_hapus on storage.objects
  as permissive
  for delete
  to authenticated
  using (((bucket_id = 'dokumen'::text) AND (name ~~ 'po/%'::text) AND (owner = auth.uid()) AND (NOT (EXISTS ( SELECT 1
   FROM purchase_orders p
  WHERE (p.lampiran = objects.name))))));

create policy rhj_po_lampiran_tulis on storage.objects
  as permissive
  for insert
  to authenticated
  with check (((bucket_id = 'dokumen'::text) AND (name ~~ 'po/%'::text) AND boleh_input_po()));
