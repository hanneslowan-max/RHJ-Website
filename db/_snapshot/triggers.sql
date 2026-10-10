-- SNAPSHOT RUJUKAN (read-only) — JANGAN dijalankan sebagai migrasi.
-- Sumber: Supabase DEV (eesdtbcualkdawhykchj), diambil 2026-10-10 dari pg_trigger / pg_get_triggerdef.
-- Isi: semua trigger non-internal (tgisinternal = false) pada tabel di skema public (144),
--       storage (7) dan auth (1); urut skema, tabel, nama trigger. Nama tabel/fungsi tanpa
--       prefiks = skema public. Trigger yang tidak berstatus enabled (O) diberi baris "-- tgenabled".
--       Skema realtime (internal Supabase) tidak disertakan. Di akhir: daftar event trigger.
-- Kebenaran tetap di DB live; snapshot ini bisa basi sesudah migrasi berikutnya.

-- ===== public =====
CREATE TRIGGER cpic_jaga BEFORE INSERT OR UPDATE ON customer_pics FOR EACH ROW EXECUTE FUNCTION jaga_rekening_pic();
CREATE TRIGGER zz_audit_customer_pics AFTER INSERT OR DELETE OR UPDATE ON customer_pics FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER customers_hp_baku BEFORE INSERT OR UPDATE OF hp ON customers FOR EACH ROW EXECUTE FUNCTION bakukan_hp_pelanggan();
CREATE TRIGGER customers_jaga_grup BEFORE INSERT OR UPDATE OF grup_id ON customers FOR EACH ROW EXECUTE FUNCTION jaga_grup_pelanggan();
CREATE TRIGGER customers_jaga_sales BEFORE UPDATE OF sales_rep_id ON customers FOR EACH ROW EXECUTE FUNCTION customers_jaga_sales();
CREATE TRIGGER customers_jaga_sales_lama BEFORE INSERT OR UPDATE OF sales_rep_lama_id ON customers FOR EACH ROW EXECUTE FUNCTION customers_jaga_sales_lama();
CREATE TRIGGER customers_jaga_status BEFORE INSERT OR UPDATE OF blacklist, alasan_blacklist, perlu_konfirmasi, alasan_konfirmasi ON customers FOR EACH ROW EXECUTE FUNCTION customers_jaga_status();
CREATE TRIGGER customers_jejak BEFORE INSERT OR UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER customers_rapi_nama BEFORE INSERT OR UPDATE OF nama, nama_lama ON customers FOR EACH ROW EXECUTE FUNCTION customers_rapi_nama();
CREATE TRIGGER customers_sales_bawaan BEFORE INSERT ON customers FOR EACH ROW EXECUTE FUNCTION customers_sales_bawaan();
CREATE TRIGGER customers_tolak_nama_ganda BEFORE INSERT OR UPDATE OF nama, nama_lama, id ON customers FOR EACH ROW EXECUTE FUNCTION customers_tolak_nama_ganda();
CREATE TRIGGER customers_zz_jaga_kembar_hitam BEFORE UPDATE OF nama, hp ON customers FOR EACH ROW EXECUTE FUNCTION jaga_ganti_kembar_hitam();
CREATE TRIGGER zz_audit_customers AFTER INSERT OR DELETE OR UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER zz_jejak_hitam AFTER INSERT OR UPDATE OF blacklist, nama, nama_lama, hp ON customers FOR EACH ROW EXECUTE FUNCTION catat_jejak_hitam();
CREATE TRIGGER documents_alur AFTER INSERT OR DELETE OR UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION dokumen_ubah_status();
CREATE TRIGGER documents_audit AFTER INSERT OR DELETE OR UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER edit_massal_audit AFTER INSERT OR DELETE OR UPDATE ON edit_massal FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER ehck_gerbang BEFORE INSERT ON ehc_klaim FOR EACH ROW EXECUTE FUNCTION jaga_gerbang_klaim();
CREATE TRIGGER ehck_jaga_cepat BEFORE UPDATE ON ehc_klaim FOR EACH ROW EXECUTE FUNCTION jaga_klaim_cepat();
CREATE TRIGGER ehck_jaga_status BEFORE INSERT OR UPDATE ON ehc_klaim FOR EACH ROW EXECUTE FUNCTION jaga_status_klaim_ehc();
CREATE TRIGGER zz_audit_ehc_klaim AFTER INSERT OR DELETE OR UPDATE ON ehc_klaim FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER ekal_jaga BEFORE INSERT OR UPDATE ON ehc_klaim_alokasi FOR EACH ROW EXECUTE FUNCTION jaga_anak_klaim_ehc();
CREATE TRIGGER zz_audit_ehc_klaim_alokasi AFTER INSERT OR DELETE OR UPDATE ON ehc_klaim_alokasi FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER ekb_jaga BEFORE INSERT OR UPDATE ON ehc_klaim_berkas FOR EACH ROW EXECUTE FUNCTION jaga_anak_klaim_ehc();
CREATE TRIGGER zz_audit_ehc_klaim_berkas AFTER INSERT OR DELETE OR UPDATE ON ehc_klaim_berkas FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER ekl_tanpa_rekening BEFORE INSERT OR UPDATE ON ehc_klaim_log FOR EACH ROW EXECUTE FUNCTION ehc_log_tanpa_rekening();
CREATE TRIGGER ekn_kunci_batch BEFORE UPDATE ON ehc_klaim_nilai FOR EACH ROW EXECUTE FUNCTION jaga_nilai_terkunci();
CREATE TRIGGER zz_audit_ehc_klaim_nilai AFTER INSERT OR DELETE OR UPDATE ON ehc_klaim_nilai FOR EACH ROW EXECUTE FUNCTION catat_perubahan_kunci('klaim_id');
CREATE TRIGGER ekp_tetap BEFORE UPDATE ON ehc_klaim_putusan FOR EACH ROW EXECUTE FUNCTION jaga_riwayat_tetap();
CREATE TRIGGER zz_audit_ehc_klaim_putusan AFTER INSERT OR UPDATE ON ehc_klaim_putusan FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER ekt_tetap BEFORE UPDATE ON ehc_klaim_tujuan FOR EACH ROW EXECUTE FUNCTION jaga_riwayat_tetap();
CREATE TRIGGER zz_audit_ehc_klaim_tujuan AFTER INSERT OR UPDATE ON ehc_klaim_tujuan FOR EACH ROW EXECUTE FUNCTION catat_perubahan_kunci('klaim_id');
CREATE TRIGGER factory_codes_audit AFTER INSERT OR DELETE OR UPDATE ON factory_codes FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER factory_codes_jejak BEFORE INSERT OR UPDATE ON factory_codes FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER harga_khusus_status AFTER INSERT OR DELETE OR UPDATE ON harga_khusus FOR EACH ROW EXECUTE FUNCTION segarkan_status_sp_khusus();
CREATE TRIGGER zz_audit_harga_khusus AFTER INSERT OR DELETE OR UPDATE ON harga_khusus FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER lines_audit AFTER INSERT OR DELETE OR UPDATE ON import_lines FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER lines_jejak BEFORE INSERT OR UPDATE ON import_lines FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER lines_nilai BEFORE INSERT OR UPDATE ON import_lines FOR EACH ROW EXECUTE FUNCTION isi_nilai_baris();
CREATE TRIGGER komisi_klaim_zz_rekening AFTER INSERT OR UPDATE OF sales_rep_id, bank, no_rekening, atas_nama ON komisi_klaim FOR EACH ROW EXECUTE FUNCTION salin_rekening_klaim_komisi();
CREATE TRIGGER komklaim_gerbang BEFORE INSERT ON komisi_klaim FOR EACH ROW EXECUTE FUNCTION jaga_gerbang_komisi();
CREATE TRIGGER zz_audit_komisi_klaim AFTER INSERT OR DELETE OR UPDATE ON komisi_klaim FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER kkn_kunci_batch BEFORE UPDATE ON komisi_klaim_nilai FOR EACH ROW EXECUTE FUNCTION jaga_nilai_terkunci();
CREATE TRIGGER zz_audit_komisi_klaim_nilai AFTER INSERT OR DELETE OR UPDATE ON komisi_klaim_nilai FOR EACH ROW EXECUTE FUNCTION catat_perubahan_kunci('klaim_id');
CREATE TRIGGER lead_events_tahap AFTER INSERT OR DELETE OR UPDATE ON lead_events FOR EACH ROW EXECUTE FUNCTION kejadian_ubah_tahap();
CREATE TRIGGER leads_jaga_tahap BEFORE UPDATE ON leads FOR EACH ROW EXECUTE FUNCTION jaga_tahap_lead();
CREATE TRIGGER leads_jejak BEFORE INSERT OR UPDATE ON leads FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER orders_audit AFTER INSERT OR DELETE OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER orders_jaga BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION jaga_kolom_owner();
CREATE TRIGGER orders_jaga_status BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION jaga_status_otomatis();
CREATE TRIGGER orders_jejak BEFORE INSERT OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER orders_nilai BEFORE INSERT OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION isi_nilai_otomatis();
CREATE TRIGGER orders_nomor_alur AFTER UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION orders_nomor_ubah_status();
CREATE TRIGGER payments_audit AFTER INSERT OR DELETE OR UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER payments_jejak BEFORE INSERT OR UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER payments_nilai BEFORE INSERT OR UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION isi_nilai_bayar_otomatis();
CREATE TRIGGER po_lines_jenis BEFORE INSERT OR UPDATE ON po_lines FOR EACH ROW EXECUTE FUNCTION jaga_jenis_baris();
CREATE TRIGGER po_lines_set_snapshot BEFORE INSERT OR UPDATE ON po_lines FOR EACH ROW EXECUTE FUNCTION jaga_set_baris_po();
CREATE TRIGGER zz_audit_po_lines AFTER INSERT OR DELETE OR UPDATE ON po_lines FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER price_list_audit AFTER INSERT OR DELETE OR UPDATE ON price_list FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER price_list_status AFTER INSERT OR DELETE OR UPDATE ON price_list FOR EACH ROW EXECUTE FUNCTION segarkan_status_sp_harga();
CREATE TRIGGER price_list_usulan BEFORE INSERT OR UPDATE ON price_list FOR EACH ROW EXECUTE FUNCTION jaga_harga_usulan();
CREATE TRIGGER product_costs_audit AFTER INSERT OR DELETE OR UPDATE ON product_costs FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE CONSTRAINT TRIGGER psetc_jaga_komposisi AFTER INSERT OR DELETE OR UPDATE ON product_set_components DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION jaga_komposisi_set();
CREATE CONSTRAINT TRIGGER pset_jaga_aktif AFTER UPDATE OF aktif ON product_sets DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (new.aktif AND NOT old.aktif) EXECUTE FUNCTION jaga_komposisi_set();
CREATE TRIGGER products_audit AFTER INSERT OR DELETE OR UPDATE ON products FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER products_jaga_kolom BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION jaga_kolom_produk();
CREATE TRIGGER products_jejak BEFORE INSERT OR UPDATE ON products FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER products_kategori BEFORE INSERT OR UPDATE ON products FOR EACH ROW EXECUTE FUNCTION isi_kategori_produk();
CREATE TRIGGER po_a_mode_ppn BEFORE INSERT OR UPDATE ON purchase_orders FOR EACH ROW EXECUTE FUNCTION sinkron_mode_ppn();
CREATE TRIGGER po_audit BEFORE INSERT OR UPDATE ON purchase_orders FOR EACH ROW EXECUTE FUNCTION po_catat_audit();
CREATE TRIGGER po_b_wajib_pelanggan BEFORE INSERT OR UPDATE OF customer_id ON purchase_orders FOR EACH ROW EXECUTE FUNCTION jaga_pelanggan_po();
CREATE TRIGGER po_c_lampiran BEFORE INSERT OR UPDATE OF lampiran ON purchase_orders FOR EACH ROW EXECUTE FUNCTION jaga_lampiran_po();
CREATE TRIGGER po_jaga_blacklist BEFORE INSERT OR UPDATE OF customer_id ON purchase_orders FOR EACH ROW EXECUTE FUNCTION jaga_blacklist_po();
CREATE TRIGGER po_mode_ppn_sp AFTER UPDATE OF mode_ppn, ppn_kena ON purchase_orders FOR EACH ROW WHEN (old.mode_ppn IS DISTINCT FROM new.mode_ppn) EXECUTE FUNCTION mode_ppn_po_ke_sp();
CREATE CONSTRAINT TRIGGER po_pelanggan_sp AFTER UPDATE OF customer_id ON purchase_orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (old.customer_id IS DISTINCT FROM new.customer_id) EXECUTE FUNCTION jaga_pelanggan_sp_po();
CREATE TRIGGER po_pemilik BEFORE INSERT ON purchase_orders FOR EACH ROW EXECUTE FUNCTION jaga_pemilik_dokumen();
CREATE TRIGGER po_z_auto_klaim_sales AFTER INSERT ON purchase_orders FOR EACH ROW EXECUTE FUNCTION po_auto_klaim_sales();
CREATE TRIGGER zz_audit_purchase_orders AFTER INSERT OR DELETE OR UPDATE ON purchase_orders FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER quote_lines_jaga_baris BEFORE INSERT ON quote_lines FOR EACH ROW EXECUTE FUNCTION jaga_baris_quote();
CREATE TRIGGER quote_lines_set_inline BEFORE INSERT OR UPDATE ON quote_lines FOR EACH ROW EXECUTE FUNCTION jaga_set_baris_quote();
CREATE TRIGGER quote_lines_set_isi BEFORE INSERT ON quote_lines FOR EACH ROW EXECUTE FUNCTION quote_lines_isi_set();
CREATE TRIGGER quotes_jaga_nomor BEFORE INSERT OR UPDATE OF nomor ON quotes FOR EACH ROW EXECUTE FUNCTION quotes_jaga_nomor();
CREATE TRIGGER quotes_jaga_sales BEFORE INSERT OR UPDATE OF sales_rep_id, customer_id ON quotes FOR EACH ROW EXECUTE FUNCTION quotes_jaga_sales();
CREATE TRIGGER quotes_jaga_top BEFORE INSERT OR UPDATE OF top, sales_rep_id ON quotes FOR EACH ROW EXECUTE FUNCTION quotes_jaga_top();
CREATE TRIGGER quotes_judul_grup BEFORE INSERT OR UPDATE OF kepada_grup, customer_id ON quotes FOR EACH ROW EXECUTE FUNCTION isi_judul_grup_penawaran();
CREATE TRIGGER quotes_kontak_pelanggan AFTER INSERT ON quotes FOR EACH ROW EXECUTE FUNCTION quotes_kontak_pelanggan();
CREATE CONSTRAINT TRIGGER quotes_wajib_baris AFTER INSERT ON quotes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION quotes_wajib_baris();
CREATE TRIGGER a_sol_harga_list BEFORE INSERT OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION isi_harga_list();
CREATE TRIGGER sol_jaga_hapus BEFORE DELETE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION jaga_hapus_baris_sp();
CREATE CONSTRAINT TRIGGER sol_jaga_saldo_ehc AFTER INSERT OR DELETE OR UPDATE ON sales_order_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION jaga_saldo_ehc_sp();
CREATE TRIGGER sol_jaga_tambah BEFORE INSERT ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION jaga_tambah_baris_sp();
CREATE TRIGGER sol_jaga_usul BEFORE DELETE OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION jaga_baris_sp_terkunci();
CREATE TRIGGER sol_jenis BEFORE INSERT OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION jaga_jenis_baris();
CREATE TRIGGER sol_qty_batal BEFORE INSERT OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION jaga_qty_batal_baris();
CREATE TRIGGER sol_set_usul BEFORE INSERT ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION isi_set_baris_usul();
CREATE TRIGGER sol_status AFTER INSERT OR DELETE OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION so_sesudah_ubah();
CREATE TRIGGER sol_total_hapus AFTER DELETE ON sales_order_lines REFERENCING OLD TABLE AS lama FOR EACH STATEMENT EXECUTE FUNCTION jaga_total_sp_vs_po();
CREATE TRIGGER sol_total_tambah AFTER INSERT ON sales_order_lines REFERENCING NEW TABLE AS baru FOR EACH STATEMENT EXECUTE FUNCTION jaga_total_sp_vs_po();
CREATE TRIGGER sol_total_ubah AFTER UPDATE ON sales_order_lines REFERENCING OLD TABLE AS lama NEW TABLE AS baru FOR EACH STATEMENT EXECUTE FUNCTION jaga_total_sp_vs_po();
CREATE TRIGGER sol_vonny_gugur AFTER INSERT OR DELETE OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION sp_vonny_gugur_baris();
CREATE TRIGGER sol_zz_list_beku BEFORE INSERT OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION beku_harga_list_baris();
CREATE TRIGGER zz_audit_sales_order_lines AFTER INSERT OR DELETE OR UPDATE ON sales_order_lines FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER so_a_dibuat_kini BEFORE INSERT ON sales_orders FOR EACH ROW EXECUTE FUNCTION isi_dibuat_pada_sp();
CREATE TRIGGER so_a_kepada_bersih BEFORE INSERT OR UPDATE OF kepada ON sales_orders FOR EACH ROW EXECUTE FUNCTION sp_kepada_bersih();
CREATE TRIGGER so_a_mode_ppn BEFORE INSERT OR UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION sinkron_mode_ppn();
CREATE TRIGGER so_a_tanggal_kini BEFORE INSERT OR UPDATE OF tanggal, no_sp ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_tanggal_sp();
CREATE TRIGGER so_audit_ins BEFORE INSERT ON sales_orders FOR EACH ROW EXECUTE FUNCTION so_audit();
CREATE TRIGGER so_cash_jaga BEFORE UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_cash_sp();
CREATE TRIGGER so_jaga_a_pelanggan BEFORE INSERT OR UPDATE OF customer_id, po_id, kepada, pelanggan_dari_po ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_pelanggan_sp_sales();
CREATE TRIGGER so_jaga_b_daftar_hitam BEFORE INSERT OR UPDATE OF batal ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_daftar_hitam_sp();
CREATE TRIGGER so_jaga_c_tahan_hitam BEFORE UPDATE OF kepada, telp, customer_id, po_id ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_tahan_hitam_sp();
CREATE TRIGGER so_jaga_gm_pct_harga BEFORE INSERT OR UPDATE OF gm_pct_harga ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_gm_pct_harga();
CREATE TRIGGER so_jaga_hapus_ehc BEFORE DELETE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_hapus_sp_ehc();
CREATE TRIGGER so_jaga_menyusul BEFORE INSERT OR UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_po_menyusul();
CREATE TRIGGER so_jaga_pembuat BEFORE UPDATE ON sales_orders FOR EACH ROW WHEN (old.dibuat_oleh IS DISTINCT FROM new.dibuat_oleh OR old.dibuat_pada IS DISTINCT FROM new.dibuat_pada) EXECUTE FUNCTION jaga_pembuat_sp();
CREATE CONSTRAINT TRIGGER so_jaga_saldo_ehc AFTER UPDATE ON sales_orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (old.batal IS DISTINCT FROM new.batal OR old.mode_ppn IS DISTINCT FROM new.mode_ppn OR old.ppn_kena IS DISTINCT FROM new.ppn_kena) EXECUTE FUNCTION jaga_saldo_ehc_sp();
CREATE TRIGGER so_jaga_sales BEFORE INSERT OR UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_kolom_sales();
CREATE TRIGGER so_jaga_status BEFORE UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_status_sp();
CREATE TRIGGER so_kirim_bertahap BEFORE UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_kirim_bertahap();
CREATE CONSTRAINT TRIGGER so_pelanggan_po AFTER UPDATE OF customer_id ON sales_orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (old.customer_id IS DISTINCT FROM new.customer_id AND new.po_id IS NOT NULL) EXECUTE FUNCTION jaga_pelanggan_sp_po();
CREATE TRIGGER so_pemilik BEFORE INSERT ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_pemilik_dokumen();
CREATE TRIGGER so_status_dok AFTER INSERT OR UPDATE OF no_surat_jalan, no_invoice, no_faktur, lunas, batal, harga_ok, vonny_ok, cash_ok, customer_id, sales_rep_id ON sales_orders FOR EACH ROW EXECUTE FUNCTION so_sesudah_ubah();
CREATE TRIGGER so_total_kepala AFTER UPDATE OF ppn_kena, po_id ON sales_orders FOR EACH ROW WHEN (old.ppn_kena IS DISTINCT FROM new.ppn_kena OR old.po_id IS DISTINCT FROM new.po_id) EXECUTE FUNCTION jaga_total_sp_kepala();
CREATE TRIGGER so_urutan_dokumen BEFORE INSERT OR UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_urutan_dokumen_sp();
CREATE TRIGGER so_vonny_gate BEFORE UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_gerbang_vonny();
CREATE TRIGGER so_vonny_gugur AFTER UPDATE ON sales_orders FOR EACH ROW WHEN (old.customer_id IS DISTINCT FROM new.customer_id OR old.kepada IS DISTINCT FROM new.kepada OR old.alamat IS DISTINCT FROM new.alamat OR old.up IS DISTINCT FROM new.up OR old.telp IS DISTINCT FROM new.telp OR old.ppn_kena IS DISTINCT FROM new.ppn_kena OR old.mode_ppn IS DISTINCT FROM new.mode_ppn OR old.catatan IS DISTINCT FROM new.catatan OR old.po_id IS NOT NULL AND old.po_id IS DISTINCT FROM new.po_id OR new.po_id IS NULL AND (old.po_menyusul IS DISTINCT FROM new.po_menyusul OR old.po_menyusul_alasan IS DISTINCT FROM new.po_menyusul_alasan) OR old.batal AND NOT new.batal) EXECUTE FUNCTION sp_vonny_gugur_kepala();
CREATE TRIGGER so_x_cash_only BEFORE INSERT OR UPDATE OF sales_rep_id, cash_minta, cash_ok ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_cash_only();
CREATE TRIGGER so_y_hanya_gm BEFORE INSERT OR UPDATE OF sales_rep_id, customer_id ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_sp_hanya_gm();
CREATE TRIGGER so_yy_hp_wajib BEFORE INSERT OR UPDATE OF customer_id, telp, batal, alamat ON sales_orders FOR EACH ROW EXECUTE FUNCTION jaga_hp_sp_tanpa_pelanggan();
CREATE TRIGGER so_z_telat BEFORE INSERT OR UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION hitung_telat_sp();
CREATE TRIGGER so_zz_flat_gm_gugur BEFORE UPDATE OF sales_rep_id ON sales_orders FOR EACH ROW EXECUTE FUNCTION gugur_setuju_flat_gm();
CREATE TRIGGER zz_audit_sales_orders AFTER INSERT OR DELETE OR UPDATE ON sales_orders FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER zz_audit_sales_rep_rekening AFTER INSERT OR DELETE OR UPDATE ON sales_rep_rekening FOR EACH ROW EXECUTE FUNCTION catat_perubahan_kunci('sales_rep_id');
CREATE TRIGGER sales_reps_dokumen_rapi BEFORE INSERT OR UPDATE OF nama_dokumen, hp_dokumen, email_dokumen ON sales_reps FOR EACH ROW EXECUTE FUNCTION sales_reps_dokumen_rapi();
CREATE TRIGGER sales_reps_lepas_pelanggan AFTER UPDATE OF aktif ON sales_reps FOR EACH ROW EXECUTE FUNCTION lepas_pelanggan_sales_nonaktif();
CREATE TRIGGER so_kirim_jaga BEFORE INSERT OR DELETE OR UPDATE ON so_kirim FOR EACH ROW EXECUTE FUNCTION jaga_so_kirim();
CREATE TRIGGER so_kirim_baris_jaga BEFORE INSERT OR DELETE OR UPDATE ON so_kirim_baris FOR EACH ROW EXECUTE FUNCTION jaga_so_kirim_baris();
CREATE TRIGGER suppliers_audit AFTER INSERT OR DELETE OR UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER sumber_audit AFTER INSERT OR DELETE OR UPDATE ON sync_sumber FOR EACH ROW EXECUTE FUNCTION catat_perubahan();
CREATE TRIGGER sumber_jejak BEFORE INSERT OR UPDATE ON sync_sumber FOR EACH ROW EXECUTE FUNCTION isi_kolom_jejak();
CREATE TRIGGER tb_jaga BEFORE UPDATE ON transfer_batch FOR EACH ROW EXECUTE FUNCTION jaga_batch();
CREATE TRIGGER tb_tandai_ditransfer AFTER UPDATE OF no_referensi ON transfer_batch FOR EACH ROW WHEN (old.no_referensi IS NULL AND new.no_referensi IS NOT NULL AND new.jenis = 'ehc'::text) EXECUTE FUNCTION tandai_ehc_ditransfer();
CREATE TRIGGER zz_audit_transfer_batch AFTER INSERT OR DELETE OR UPDATE ON transfer_batch FOR EACH ROW EXECUTE FUNCTION catat_perubahan();

-- ===== auth / storage =====
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION buat_profil_baru();
CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();
CREATE TRIGGER protect_bucket_control_insert BEFORE INSERT ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.protect_bucket_control_columns('service_role');
CREATE TRIGGER protect_bucket_control_update BEFORE UPDATE OF lifecycle_configuration, lifecycle_configuration_generation ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.protect_bucket_control_columns();
CREATE TRIGGER protect_bucket_control_update_role AFTER UPDATE OF lifecycle_configuration, lifecycle_configuration_generation ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_lifecycle_service_role('service_role');
CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();
CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();
CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();

-- ===== event trigger (pg_event_trigger) =====
-- issue_graphql_placeholder: ON sql_drop EXECUTE FUNCTION set_graphql_placeholder | enabled=O | owner=supabase_admin | tags=DROP EXTENSION
-- issue_pg_cron_access: ON ddl_command_end EXECUTE FUNCTION grant_pg_cron_access | enabled=O | owner=supabase_admin | tags=CREATE EXTENSION
-- issue_pg_graphql_access: ON ddl_command_end EXECUTE FUNCTION grant_pg_graphql_access | enabled=O | owner=supabase_admin | tags=CREATE EXTENSION
-- issue_pg_net_access: ON ddl_command_end EXECUTE FUNCTION grant_pg_net_access | enabled=O | owner=supabase_admin | tags=CREATE EXTENSION
-- jaga_view_komisi: ON ddl_command_end EXECUTE FUNCTION jaga_view_komisi_tertutup | enabled=A | owner=postgres | tags=CREATE VIEW, ALTER VIEW
-- jaga_view_komisi_b: ON ddl_command_end EXECUTE FUNCTION jaga_view_komisi_tertutup | enabled=A | owner=postgres | tags=ALTER TABLE, CREATE RULE
-- jaga_view_komisi_c: ON ddl_command_end EXECUTE FUNCTION jaga_view_komisi_tertutup | enabled=A | owner=postgres | tags=CREATE TABLE, CREATE TABLE AS, SELECT INTO, CREATE MATERIALIZED VIEW, ALTER MATERIALIZED VIEW, CREATE FOREIGN TABLE, ALTER FOREIGN TABLE, IMPORT FOREIGN SCHEMA
-- pgrst_ddl_watch: ON ddl_command_end EXECUTE FUNCTION pgrst_ddl_watch | enabled=O | owner=supabase_admin
-- pgrst_drop_watch: ON sql_drop EXECUTE FUNCTION pgrst_drop_watch | enabled=O | owner=supabase_admin
