-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email text,
  nama text,
  peran text NOT NULL DEFAULT 'pending'::text CHECK (peran = ANY (ARRAY['owner'::text, 'gm'::text, 'staff'::text, 'finance'::text, 'sales'::text, 'liesian'::text, 'ichi'::text, 'vonny'::text, 'lenni'::text, 'selfie'::text, 'pending'::text, 'nonaktif'::text])),
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);
CREATE TABLE public.orders (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  no_invoice text NOT NULL,
  supplier text NOT NULL,
  tanggal_order date,
  mata_uang text NOT NULL DEFAULT 'CNY'::text CHECK (mata_uang = ANY (ARRAY['CNY'::text, 'JPY'::text, 'USD'::text, 'EUR'::text, 'IDR'::text])),
  total_nilai numeric CHECK (total_nilai IS NULL OR total_nilai >= 0::numeric),
  kurs_estimasi numeric CHECK (kurs_estimasi IS NULL OR kurs_estimasi > 0::numeric),
  nilai_estimasi numeric,
  status_produksi text NOT NULL DEFAULT 'Order Diterima'::text CHECK (status_produksi = ANY (ARRAY['Order Diterima'::text, 'Proses Produksi'::text, 'Dalam Pengiriman'::text, 'Proses Customs'::text, 'Sudah Diterima'::text])),
  etd date,
  eta date,
  tanggal_tiba date,
  status_dokumen text,
  status_customs text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  no_proforma text,
  no_do text,
  no_invoice_awal text,
  no_invoice_direvisi_oleh uuid,
  no_invoice_direvisi_pada timestamp with time zone,
  CONSTRAINT orders_pkey PRIMARY KEY (id),
  CONSTRAINT orders_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT orders_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.payments (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  order_id bigint NOT NULL,
  jenis text NOT NULL DEFAULT 'DP / Uang Muka'::text CHECK (jenis = ANY (ARRAY['DP / Uang Muka'::text, 'Termin'::text, 'Pelunasan'::text, 'Biaya Lain'::text])),
  jumlah_tagihan numeric,
  jatuh_tempo date,
  metode text DEFAULT 'T/T (Transfer)'::text,
  tanggal_bayar date,
  jumlah_dibayar numeric CHECK (jumlah_dibayar IS NULL OR jumlah_dibayar >= 0::numeric),
  kurs_bayar numeric CHECK (kurs_bayar IS NULL OR kurs_bayar > 0::numeric),
  nilai_idr numeric,
  referensi text,
  pic text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT payments_pkey PRIMARY KEY (id),
  CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT payments_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT payments_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tabel text NOT NULL,
  baris_id bigint,
  aksi text NOT NULL,
  oleh uuid,
  oleh_email text,
  pada timestamp with time zone NOT NULL DEFAULT now(),
  sebelum jsonb,
  sesudah jsonb,
  CONSTRAINT audit_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.suppliers (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nama text NOT NULL UNIQUE,
  negara text,
  alias ARRAY NOT NULL DEFAULT '{}'::text[],
  aktif boolean NOT NULL DEFAULT true,
  catatan text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT suppliers_pkey PRIMARY KEY (id)
);
CREATE TABLE public.products (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_lama text UNIQUE,
  kode text NOT NULL,
  brand text NOT NULL,
  kelompok text,
  fungsi text CHECK (fungsi IS NULL OR (fungsi = ANY (ARRAY['Hidup / Swivel'::text, 'Mati / Rigid'::text, 'Rem / Brake'::text]))),
  satuan text NOT NULL DEFAULT 'pcs'::text CHECK (satuan = ANY (ARRAY['pcs'::text, 'set'::text, 'unit'::text])),
  diameter_mm numeric,
  hal_katalog text,
  yakin text,
  sumber_barang text CHECK (sumber_barang = ANY (ARRAY['impor'::text, 'lokal'::text, 'campuran'::text])),
  aktif boolean NOT NULL DEFAULT true,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  fungsi_lama text,
  bahan text CHECK (bahan IS NULL OR (bahan = ANY (ARRAY['CB'::text, 'Karet'::text, 'Nylon'::text, 'Polyurethane'::text]))),
  usulan boolean NOT NULL DEFAULT false,
  usulan_teks text,
  kategori text NOT NULL CHECK (kategori = ANY (ARRAY['Roda'::text, 'Pallet Mesh'::text, 'Hospital'::text, 'Filing Cabinet'::text, 'Trolley'::text, 'Hand Pallet'::text, 'Lainnya'::text])),
  CONSTRAINT products_pkey PRIMARY KEY (id),
  CONSTRAINT products_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT products_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
-- tipe_roda(kode) [berkas 94]: kunci tipe roda dari kode — produk yang hanya beda fungsi (H/M/R/S,
--   OSJ/OSK/OSJB, OSNJ/OSNJB/OSNBK, SPJ/SPK/SPJB, HSUCJ/HSUCJB/HSUCK, JCB/KCB/JBCB, TSH/TFH/TSHJB,
--   Hammer 320S/320SR, 500BPS/500BPR) mendapat kunci sama; dibandingkan tanpa spasi.
CREATE TABLE public.product_sets (   -- #1 set roda (berkas 74; dipakai PO sejak 85; aturan & snapshot 94)
  id bigint NOT NULL DEFAULT nextval('product_sets_id_seq'::regclass),
  kode text UNIQUE,
  nama text NOT NULL,
  kategori text,
  catatan text,
  aktif boolean NOT NULL DEFAULT true,
  dibuat_oleh uuid DEFAULT auth.uid(),
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone,
  CONSTRAINT product_sets_pkey PRIMARY KEY (id)
);
CREATE TABLE public.product_set_components (
  id bigint NOT NULL DEFAULT nextval('product_set_components_id_seq'::regclass),
  set_id bigint NOT NULL,
  product_id bigint NOT NULL,
  qty numeric NOT NULL DEFAULT 1 CHECK (qty > 0::numeric),
  harga_nett numeric NOT NULL DEFAULT 0 CHECK (harga_nett >= 0::numeric),
  urut integer NOT NULL DEFAULT 1,
  CONSTRAINT product_set_components_pkey PRIMARY KEY (id),
  CONSTRAINT product_set_components_set_id_fkey FOREIGN KEY (set_id) REFERENCES public.product_sets(id) ON DELETE CASCADE,
  CONSTRAINT product_set_components_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
-- View product_set_ringkas: harga_set = sum(qty*harga_nett), total_pcs, jumlah_komponen.
-- Aturan set roda (#1, berkas 94) = periksa_komposisi_set(komponen jsonb) -> NULL sah / pesan:
--   tepat 4 pcs, qty bulat, satu kategori + merek + tipe_roda, fungsi tercatat, satu produk per fungsi,
--   kombinasi 4R / 4H / 4M / 2R+2H / 2R+2M / 2H+2M, bukan usulan, harga_nett >= 0 & <= 2 desimal.
--   Ditegakkan: RPC simpan_set; constraint trigger DEFERRABLE INITIALLY DEFERRED psetc_jaga_komposisi
--   (product_set_components) & pset_jaga_aktif (product_sets, saat diaktifkan) -> jaga_komposisi_set();
--   dan saat set dipakai baris PO (po_lines_set_snapshot).
-- #28 (berkas 108) SET INLINE: set juga boleh disusun langsung di baris po_lines / quote_lines
--   (set_id NULL, set_komponen [{product_id,qty,urut}] qty per 1 set) tanpa baris product_sets —
--   dipakai sales yang tidak berhak menulis data master. Diperiksa periksa_komposisi_set yang sama.
--   Helper: set_inline_rapi(jsonb) [internal: normalkan, buang harga_nett], label_set_inline(jsonb)
--   -> 'Set <tipe> (2 hidup + 2 mati)'. RPC pilihan_tipe_roda() (INVOKER, ikut RLS products): produk
--   aktif non-usulan berfungsi Rem/Hidup/Mati + kunci tipe (kategori|brand|tipe_roda tanpa spasi).
-- RPC (SECURITY INVOKER, hak = RLS): simpan_set(p_id, p_kepala, p_komponen) -> id, atomik;
--   hapus_set(p_id) -> teks: hapus bila belum dipakai PO, bila sudah dipakai -> aktif=false.
-- RLS: pset_baca/psetc_baca = boleh_lihat_produk(); tambah/ubah (dan hapus komponen) = boleh_ubah_impor()
--   (owner/gm/staff); pset_hapus = boleh_hapus() (owner). quote_lines.set_id ON DELETE SET NULL.
CREATE TABLE public.factory_codes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  supplier_id bigint NOT NULL,
  kode_pabrik text NOT NULL,
  product_id bigint,
  id_lama text,
  varian text,
  pembeda text,
  diameter_mm numeric,
  fungsi text,
  hs text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT factory_codes_pkey PRIMARY KEY (id),
  CONSTRAINT factory_codes_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id),
  CONSTRAINT factory_codes_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT factory_codes_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT factory_codes_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.price_list (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  product_id bigint NOT NULL,
  harga numeric NOT NULL CHECK (harga >= 0::numeric),
  berlaku_dari date NOT NULL DEFAULT CURRENT_DATE,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  batch_id bigint,
  CONSTRAINT price_list_pkey PRIMARY KEY (id),
  CONSTRAINT price_list_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT price_list_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT price_list_batch_fk FOREIGN KEY (batch_id) REFERENCES public.edit_massal(id)
);
CREATE TABLE public.product_costs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  product_id bigint NOT NULL,
  hpp numeric NOT NULL CHECK (hpp >= 0::numeric),
  berlaku_dari date NOT NULL DEFAULT CURRENT_DATE,
  sumber text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  batch_id bigint,
  CONSTRAINT product_costs_pkey PRIMARY KEY (id),
  CONSTRAINT product_costs_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT product_costs_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT product_costs_batch_fk FOREIGN KEY (batch_id) REFERENCES public.edit_massal(id)
);
CREATE TABLE public.documents (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  order_id bigint NOT NULL,
  jenis text NOT NULL DEFAULT 'Lainnya'::text CHECK (jenis = ANY (ARRAY['Proforma Invoice'::text, 'Commercial Invoice'::text, 'Packing List'::text, 'Bill of Lading'::text, 'Certificate of Origin'::text, 'Delivery Order'::text, 'PIB'::text, 'Bukti Transfer'::text, 'Invoice EMKL'::text, 'Sales Contract'::text, 'Lainnya'::text])) NOT VALI),
  nama_berkas text NOT NULL,
  path text NOT NULL UNIQUE,
  ukuran bigint,
  mime text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT documents_pkey PRIMARY KEY (id),
  CONSTRAINT documents_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT documents_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.import_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  order_id bigint NOT NULL,
  baris integer,
  kode_pabrik text NOT NULL,
  factory_code_id bigint,
  product_id bigint,
  keterangan text,
  qty numeric NOT NULL CHECK (qty > 0::numeric),
  harga_satuan numeric NOT NULL CHECK (harga_satuan >= 0::numeric),
  nilai numeric,
  satuan text DEFAULT 'pcs'::text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT import_lines_pkey PRIMARY KEY (id),
  CONSTRAINT import_lines_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT import_lines_factory_code_id_fkey FOREIGN KEY (factory_code_id) REFERENCES public.factory_codes(id),
  CONSTRAINT import_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT import_lines_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT import_lines_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.sync_sumber (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nama text NOT NULL UNIQUE,
  sheet_id text NOT NULL,
  gid text NOT NULL DEFAULT '0'::text,
  kolom_kode text NOT NULL DEFAULT 'kode'::text,
  kolom_harga text NOT NULL DEFAULT 'harga'::text,
  aktif boolean NOT NULL DEFAULT true,
  jadwal_aktif boolean NOT NULL DEFAULT true,
  otomatis boolean NOT NULL DEFAULT false,
  min_baris integer NOT NULL DEFAULT 700 CHECK (min_baris >= 0),
  maks_ubah_persen numeric NOT NULL DEFAULT 20 CHECK (maks_ubah_persen >= 0::numeric AND maks_ubah_persen <= 100::numeric),
  maks_lonjakan_persen numeric NOT NULL DEFAULT 50 CHECK (maks_lonjakan_persen >= 0::numeric AND maks_lonjakan_persen <= 1000::numeric),
  boleh_hapus boolean NOT NULL DEFAULT false,
  terakhir_tarik timestamp with time zone,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT sync_sumber_pkey PRIMARY KEY (id),
  CONSTRAINT sync_sumber_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT sync_sumber_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.sync_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sumber_id bigint,
  waktu timestamp with time zone NOT NULL DEFAULT now(),
  hasil text NOT NULL CHECK (hasil = ANY (ARRAY['pratinjau'::text, 'diterapkan'::text, 'ditolak'::text, 'galat'::text])),
  baris_dibaca integer NOT NULL DEFAULT 0,
  naik integer NOT NULL DEFAULT 0,
  turun integer NOT NULL DEFAULT 0,
  baru integer NOT NULL DEFAULT 0,
  hilang integer NOT NULL DEFAULT 0,
  sama integer NOT NULL DEFAULT 0,
  tak_dikenal integer NOT NULL DEFAULT 0,
  alasan text,
  rincian jsonb,
  oleh uuid,
  oleh_email text,
  CONSTRAINT sync_log_pkey PRIMARY KEY (id),
  CONSTRAINT sync_log_sumber_id_fkey FOREIGN KEY (sumber_id) REFERENCES public.sync_sumber(id),
  CONSTRAINT sync_log_oleh_fkey FOREIGN KEY (oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.edit_massal (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  jenis text NOT NULL CHECK (jenis = ANY (ARRAY['harga'::text, 'hpp'::text, 'kelompok'::text, 'bracket'::text, 'bahan'::text, 'ukuran'::text])),
  cara text NOT NULL CHECK (cara = ANY (ARRAY['tetap'::text, 'persen'::text, 'rupiah'::text, 'tempel'::text, 'kosongkan'::text])),
  nilai numeric,
  pembulatan integer NOT NULL DEFAULT 0,
  berlaku_dari date NOT NULL,
  jumlah_baris integer NOT NULL,
  catatan text,
  dipaksa boolean NOT NULL DEFAULT false,
  dibatalkan_pada timestamp with time zone,
  dibatalkan_oleh uuid,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  nilai_teks text,
  CONSTRAINT edit_massal_pkey PRIMARY KEY (id),
  CONSTRAINT edit_massal_dibatalkan_oleh_fkey FOREIGN KEY (dibatalkan_oleh) REFERENCES auth.users(id),
  CONSTRAINT edit_massal_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.edit_massal_nilai (
  batch_id bigint NOT NULL,
  product_id bigint NOT NULL,
  lama text,
  baru text,
  CONSTRAINT edit_massal_nilai_pkey PRIMARY KEY (batch_id, product_id),
  CONSTRAINT edit_massal_nilai_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.edit_massal(id),
  CONSTRAINT edit_massal_nilai_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
CREATE TABLE public.sales_reps (
  id bigint NOT NULL DEFAULT nextval('sales_reps_id_seq'::regclass),
  nama text NOT NULL,
  jenis text NOT NULL DEFAULT 'orang'::text CHECK (jenis = ANY (ARRAY['orang'::text, 'cabang'::text])),
  cabang text,
  profile_id uuid,
  aktif boolean NOT NULL DEFAULT true,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  komisi_flat_pct numeric CHECK (komisi_flat_pct IS NULL OR komisi_flat_pct >= 0::numeric AND komisi_flat_pct <= 0.5),
  cash_only boolean NOT NULL DEFAULT false,
  CONSTRAINT sales_reps_pkey PRIMARY KEY (id),
  CONSTRAINT sales_reps_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES auth.users(id)
);
-- komisi_flat_pct & cash_only [berkas 68, #22]: Riksa (8) & Michael (7) = 0.01 & true. komisi_flat_pct
--   mengalahkan tier/harga khusus/cash di so_baris_hitung. cash_only ditegakkan trigger so_x_cash_only di
--   sales_orders [berkas 95]. RLS rep_baca = boleh_baca() (tanpa ichi/liesian/selfie) → FE memakai
--   RPC sales_rep_cash_only() -> bigint[] (authenticated; pending/nonaktif = {}) [berkas 95].
CREATE TABLE public.customers (
  id bigint NOT NULL DEFAULT nextval('customers_id_seq'::regclass),
  nama text NOT NULL,
  hp text CHECK (hp IS NULL OR hp ~ '^[1-9][0-9]{8,15}$'::text),
  hp_lain ARRAY NOT NULL DEFAULT '{}'::text[],
  lokasi text,
  pic text,
  catatan text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  diubah_pada timestamp with time zone,
  diubah_oleh uuid,
  industri text,
  cabang text,
  salesman_teks text,
  telp text,
  sumber text,
  blacklist boolean NOT NULL DEFAULT false,
  alasan_blacklist text,
  urut_sumber smallint DEFAULT 
CASE sumber
    WHEN 'master'::text THEN 1
    WHEN 'keduanya'::text THEN 1
    WHEN 'blacklist'::text THEN 1
    WHEN 'pipeline'::text THEN 2
    ELSE 3
END,
  perlu_konfirmasi boolean NOT NULL DEFAULT false,
  alasan_konfirmasi text,
  sales_rep_id bigint,
  nama_lama text,       -- [berkas 71/100, #20] nama asli sebelum dirapikan (cadangan sekali; dikunci trigger)
  industri_lama text,   -- [#25] teks industri dari sheet lama (apa adanya, tidak diubah)
  nama_urut text GENERATED ALWAYS AS (regexp_replace(lower(COALESCE(nama, ''::text)), '^(pt|cv|ud|pd|tb|fa|toko|rs)\s+'::text, ''::text)) STORED,  -- [berkas 100] urut A→Z tanpa awalan badan usaha
  CONSTRAINT customers_industri_cek CHECK (industri IS NULL OR industri = ANY (ARRAY['Otomotif'::text, 'Non Otomotif'::text, 'Bengkel Otomotif'::text])),
  CONSTRAINT customers_pkey PRIMARY KEY (id),
  CONSTRAINT customers_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT customers_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id),
  CONSTRAINT customers_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id)
);
-- customers [berkas 100, #20]: trigger customers_rapi_nama (BEFORE INSERT / UPDATE OF nama, nama_lama) merapikan
--   nama lewat rhj_nama_rapi() (PT/CV/UD/PD/TB/FA/Toko ke depan, Tbk di belakang, isi kurung, singkatan
--   dipertahankan); nama asli → nama_lama bila masih kosong; nama_lama tak bisa diubah lewat REST. Jalur admin
--   (terapkan_rapi_nama / pulihkan_nama_pelanggan, gerbang owner/gm/vonny) memakai GUC rhj.lewati_rapi_nama.
--   Pulihkan melewati baris yang namanya sudah diganti manual (rhj_nama_sidik beda). Index customers_nama_urut_idx.
-- customers.industri [berkas 101, #25]: diisi lewat form CRM (RLS cust_ubah) atau RPC
--   set_industri_pelanggan(p_customer, p_industri) (owner/gm/vonny, atau owner/gm/staff/sales — sales hanya
--   pelanggan miliknya/belum bertuan). Tebakan dari industri_lama: rhj_industri_tebak(text).
--   [berkas 105] peta dibuat lebih konservatif: kata generik (supplier/trading/distributor/toko/store/shop/
--   service/equipment/peralatan/perdagangan/grosir/…) tanpa kata industri yang jelas → NULL (diisi manual).
-- cek_pemilik_pelanggan(p_nama, p_rep) [berkas 87, diubah 105]: cocok per kata setelah tanda baca & PT/CV/UD/PD/
--   TB/Tbk/Toko dibuang di kedua sisi, ke nama DAN nama_lama; keluaran tetap nama + nama sales (maks 5).
CREATE TABLE public.leads (
  id bigint NOT NULL DEFAULT nextval('leads_id_seq'::regclass),
  customer_id bigint NOT NULL,
  sales_rep_id bigint,
  product_id bigint,
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  kategori text,
  permintaan text,
  catatan text,
  no_so text,
  tanggal_ok date,
  dipegang_sales_lain boolean NOT NULL DEFAULT false,
  tahap text NOT NULL DEFAULT 'Lead Baru'::text CHECK (tahap = ANY (ARRAY['Lead Baru'::text, 'Penawaran Terkirim'::text, 'Menunggu Kabar'::text, 'Deal'::text, 'Batal'::text])),
  alasan_batal text,
  baris_sheet integer,
  tanggal_diperbaiki boolean NOT NULL DEFAULT false,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  diubah_pada timestamp with time zone,
  diubah_oleh uuid,
  CONSTRAINT leads_pkey PRIMARY KEY (id),
  CONSTRAINT leads_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT leads_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT leads_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT leads_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT leads_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.lead_nilai (
  lead_id bigint NOT NULL,
  nilai numeric,
  nilai_ok numeric,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  CONSTRAINT lead_nilai_pkey PRIMARY KEY (lead_id),
  CONSTRAINT lead_nilai_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id),
  CONSTRAINT lead_nilai_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.lead_events (
  id bigint NOT NULL DEFAULT nextval('lead_events_id_seq'::regclass),
  lead_id bigint NOT NULL,
  jenis text NOT NULL CHECK (jenis = ANY (ARRAY['dibuat'::text, 'penawaran'::text, 'follow_up'::text, 'visit'::text, 'order'::text, 'batal'::text])),
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  keterangan text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  CONSTRAINT lead_events_pkey PRIMARY KEY (id),
  CONSTRAINT lead_events_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id),
  CONSTRAINT lead_events_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.quotes (
  id bigint NOT NULL DEFAULT nextval('quotes_id_seq'::regclass),
  lead_id bigint,
  customer_id bigint NOT NULL,
  nomor text NOT NULL,
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  berlaku_hari integer,
  kepada text,
  catatan text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  sales_rep_id bigint,
  CONSTRAINT quotes_pkey PRIMARY KEY (id),
  CONSTRAINT quotes_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE SET NULL,
  CONSTRAINT quotes_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT quotes_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT quotes_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id)
);
-- UNIQUE INDEX quotes_nomor_uniq (nomor); INDEX quotes_sales_rep_idx (sales_rep_id)  [berkas 87]
-- berlaku_hari NULL = tanpa batas (#5).
-- Trigger quotes_jaga_sales (BEFORE INSERT / UPDATE OF sales_rep_id, customer_id) [berkas 87]:
--   isi dibuat_oleh/dibuat_pada; sales -> sales_rep_id = dirinya (tak bisa sales lain);
--   vonny wajib ada sales; sales & vonny: pelanggan bertuan hanya atas nama pemegangnya.
-- Trigger quotes_jaga_nomor (BEFORE INSERT / UPDATE OF nomor) [berkas 93]: INSERT tanpa nomor → diisi
--   counter; selain owner nomor wajib yang sudah dikeluarkan counter (format baku, urut ≤ counter);
--   UPDATE nomor hanya owner. auth.uid() null tidak dijaga.
-- RLS [berkas 87, 93]: quote_baca = vonny / boleh_lihat_semua_lead() / (peran sales AND
--   sales_rep_id = sales_rep_saya(), atau lead lama milik sales itu) — sales nonaktif/pending yang
--   masih tertaut tidak melihat apa pun; quote_tambah = crm/vonny + pelanggan_saya + sales=dirinya;
--   quote_ubah = owner/gm/staff/vonny. Simpan lewat RPC simpan_penawaran(p_kepala, p_baris):
--   nomor diambil ulang bila bentrok quotes_nomor_uniq (maks 10x) [berkas 93].
CREATE TABLE public.quote_lines (
  id bigint NOT NULL DEFAULT nextval('quote_lines_id_seq'::regclass),
  quote_id bigint NOT NULL,
  product_id bigint,
  deskripsi text NOT NULL,
  qty numeric NOT NULL DEFAULT 1,
  satuan text NOT NULL DEFAULT 'pcs'::text,
  harga numeric NOT NULL,
  harga_list numeric,
  urut integer NOT NULL DEFAULT 1,
  spesifikasi text,
  set_id bigint,
  set_komponen jsonb,                                         -- #28 (berkas 108): isi set inline
  CONSTRAINT quote_lines_pkey PRIMARY KEY (id),
  CONSTRAINT quote_lines_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES public.quotes(id) ON DELETE CASCADE,
  CONSTRAINT quote_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT quote_lines_set_id_fkey FOREIGN KEY (set_id) REFERENCES public.product_sets(id) ON DELETE SET NULL,
  CONSTRAINT quote_lines_qty_positif CHECK (qty > 0::numeric) NOT VALID,
  CONSTRAINT quote_lines_harga_wajar CHECK (harga >= 0::numeric) NOT VALID,
  CONSTRAINT quote_lines_produk_atau_set CHECK (product_id IS NULL OR set_id IS NULL) NOT VALID,
  CONSTRAINT quote_lines_set_inline CHECK (set_komponen IS NULL OR (set_id IS NULL AND product_id IS NULL
    AND qty = trunc(qty) AND jsonb_typeof(set_komponen) = 'array'))   -- berkas 108
);
-- Baris set (#1, berkas 87): product_id NULL + set_id, satuan 'set', harga = harga per set.
-- Set inline (#28, berkas 108): product_id & set_id NULL, set_komponen terisi, qty bulat; trigger
--   quote_lines_set_inline (jaga_set_baris_quote) menormalkan + periksa_komposisi_set, satuan := 'set',
--   deskripsi kosong/'—' := label_set_inline. simpan_penawaran menerima set_komponen per baris.
-- RLS: ql_baca = boleh_lihat_quote(quote_id); ql_tulis = boleh_tulis_quote(quote_id).
CREATE TABLE public.quote_counter (
  tahun integer NOT NULL,
  bulan integer NOT NULL,
  urut integer NOT NULL DEFAULT 0,
  CONSTRAINT quote_counter_pkey PRIMARY KEY (tahun, bulan)
);
-- Nomor: nomor_penawaran_baru(tanggal) (SECURITY DEFINER, crm/vonny) menaikkan counter dan MELOMPATI
--   nomor yang sudah ada di quotes; format lewat nomor_penawaran_format(urut, tahun, bulan) =
--   'NNN/PQ/MCE/<bulan romawi>/<tahun>', ≥ 1000 tidak dipotong [berkas 93]. RLS tanpa policy →
--   tabel ini hanya disentuh lewat fungsi.
CREATE TABLE public.purchase_orders (
  id bigint NOT NULL DEFAULT nextval('purchase_orders_id_seq'::regclass),
  no_po text NOT NULL CHECK (btrim(no_po) <> ''::text),
  tanggal date NOT NULL,
  customer_id bigint,
  nama_customer text NOT NULL,
  alamat text,
  sales_rep_id bigint,
  ppn_kena boolean NOT NULL DEFAULT true,
  lampiran text,
  catatan text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  diubah_pada timestamp with time zone,
  diubah_oleh uuid,
  batal boolean NOT NULL DEFAULT false,
  alasan_batal text,
  dibatalkan_pada timestamp with time zone,
  dibatalkan_oleh uuid,
  CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
  CONSTRAINT purchase_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT purchase_orders_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT purchase_orders_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT purchase_orders_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id),
  CONSTRAINT purchase_orders_dibatalkan_oleh_fkey FOREIGN KEY (dibatalkan_oleh) REFERENCES auth.users(id)
);
-- Constraint trigger po_pelanggan_sp (AFTER UPDATE OF customer_id, DEFERRABLE INITIALLY DEFERRED)
--   [berkas 89] -> jaga_pelanggan_sp_po(): SP (tidak batal) yang menunjuk PO ini harus berpelanggan sama.
CREATE TABLE public.po_lines (
  id bigint NOT NULL DEFAULT nextval('po_lines_id_seq'::regclass),
  po_id bigint NOT NULL,
  urut integer NOT NULL DEFAULT 1,
  product_id bigint,
  deskripsi text,
  qty numeric(14,2) NOT NULL CHECK (qty > 0::numeric),
  harga numeric(14,2) NOT NULL CHECK (harga >= 0::numeric),
  jenis text NOT NULL DEFAULT 'barang'::text CHECK (jenis = ANY (ARRAY['barang'::text, 'biaya'::text])),
  keterangan text,                                            -- #6: catatan per baris
  diskon numeric NOT NULL DEFAULT 0 CHECK (diskon >= 0::numeric),   -- #7
  diskon_tipe text NOT NULL DEFAULT 'rp'::text CHECK (diskon_tipe = ANY (ARRAY['rp'::text, 'persen'::text])),
  set_id bigint,                                              -- #1 (berkas 85): baris SET
  set_komponen jsonb,                                         -- #1 (berkas 94): snapshot komponen set
  CONSTRAINT po_lines_pkey PRIMARY KEY (id),
  CONSTRAINT po_lines_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  CONSTRAINT po_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT po_lines_set_id_fkey FOREIGN KEY (set_id) REFERENCES public.product_sets(id),
  -- berkas 94 (#7/#1):
  CONSTRAINT po_lines_diskon_maks CHECK (CASE WHEN diskon_tipe = 'persen' THEN diskon <= 100 ELSE diskon <= qty * harga END),
  CONSTRAINT po_lines_diskon_sen CHECK (CASE WHEN diskon_tipe = 'persen'
    THEN qty * harga * diskon / 100 = trunc(qty * harga * diskon / 100, 2) ELSE diskon = trunc(diskon, 2) END),
  -- berkas 108 (#28): dua CHECK di bawah juga berlaku untuk set inline (set_komponen terisi)
  CONSTRAINT po_lines_set_qty_bulat CHECK ((set_id IS NULL AND set_komponen IS NULL) OR qty = trunc(qty)),
  CONSTRAINT po_lines_set_bukan_produk CHECK ((set_id IS NULL AND set_komponen IS NULL)
    OR (product_id IS NULL AND jenis = 'barang')),
  CONSTRAINT po_lines_set_komponen_larik CHECK (set_komponen IS NULL OR jsonb_typeof(set_komponen) = 'array'),
  -- berkas 107 (#12): baris berdiskon → qty*harga habis dalam sen (harga_nett SP 2 desimal harus bisa menyamai PO)
  CONSTRAINT po_lines_diskon_bruto_sen CHECK (COALESCE(diskon, 0) = 0 OR qty * harga = trunc(qty * harga, 2))
);
-- Nilai baris = qty*harga − potongan (potongan = diskon Rp, atau qty*harga*diskon/100) — rumus po_ringkas.
-- Baris SET (#1): jenis 'barang', product_id NULL, set_id terisi, harga = harga per set, qty = jumlah set
--   (bulat), deskripsi = nama set. set_komponen = [{product_id,qty,harga_nett,urut}] diisi trigger
--   po_lines_set_snapshot (BEFORE INSERT/UPDATE -> jaga_set_baris_po, berkas 94): diambil dari definisi
--   set saat baris disimpan (set wajib aktif & sah menurut periksa_komposisi_set), nilai dari klien
--   diabaikan, tidak bisa diubah langsung; putuskan_ubah (rhj.usul='on') membawa snapshot lama bila
--   set_id sama. SP dari PO memecah set ke pcs menurut snapshot ini (FE spBarisDariPo): nilai bersih baris
--   dibagi PERSIS (maks. 2 baris SP per item: n dan n+1 satuan Rp 1 / 1 sen) → grand total SP = PO.
-- Set INLINE (#28, berkas 108): set_id NULL + set_komponen [{product_id,qty,urut}] dari penginput
--   (dinormalkan set_inline_rapi, wajib lolos periksa_komposisi_set, deskripsi kosong := label_set_inline),
--   harga = harga PER SET dari PO customer. Tidak bisa diubah langsung; putuskan_ubah membawanya apa adanya
--   (po_baris_usul_lengkap tak pernah mengambil set_komponen dari payload; dibuang bila baris diubah jadi
--   produk/biaya). SP: nilai bersih dibagi ke komponen sebanding qty × price list berlaku (tanpa price list
--   -> rata per pcs), dipecah persis sampai sen (FE bobotSetInline/alokasiSetSen).
-- Trigger lain: po_lines_jenis (jaga_jenis_baris — barang tanpa product_id sah bila set_id ATAU
--   set_komponen terisi, berkas 108), zz_audit_po_lines.
-- RLS: pol_baca (PO terbaca), pol_tambah (PO terbaca + boleh_input_po), pol_ubah/pol_hapus
--   (boleh_ubah_langsung = owner/gm). Perubahan oleh peran lain lewat ajukan_ubah → putuskan_ubah:
--   cabang po melengkapi baris usulan dari baris tersimpan (po_baris_usul_lengkap: set_id, set_komponen,
--   diskon, diskon_tipe, keterangan) dan memeriksanya (periksa_baris_po_usul) [berkas 94].
CREATE TABLE public.sp_counter (
  tahun integer NOT NULL,
  bulan integer NOT NULL,
  terakhir integer NOT NULL DEFAULT 0,
  CONSTRAINT sp_counter_pkey PRIMARY KEY (tahun, bulan)
);
CREATE TABLE public.sales_orders (
  id bigint NOT NULL DEFAULT nextval('sales_orders_id_seq'::regclass),
  no_sp text NOT NULL UNIQUE,
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  po_id bigint,
  customer_id bigint,
  quote_id bigint,
  sales_rep_id bigint,
  kepada text NOT NULL,
  alamat text,
  up text,
  telp text,
  no_seri text,
  ppn_kena boolean NOT NULL DEFAULT true,
  catatan text,
  kirim_syarat text,
  bayar_syarat text,
  harga_ok boolean,
  gm_pct numeric,
  gm_oleh uuid,
  gm_pada timestamp with time zone,
  ehc_dini_minta boolean NOT NULL DEFAULT false,
  ehc_dini_ok boolean NOT NULL DEFAULT false,
  no_surat_jalan text,
  tgl_surat_jalan date,
  no_invoice text,
  tgl_invoice date,
  lunas boolean NOT NULL DEFAULT false,
  tgl_lunas date,
  telat boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'draft'::text CHECK (status = ANY (ARRAY['draft'::text, 'menunggu gm'::text, 'di gudang'::text, 'terkirim'::text, 'tertagih'::text, 'lunas'::text, 'batal'::text])),
  batal boolean NOT NULL DEFAULT false,
  alasan_batal text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  diubah_pada timestamp with time zone,
  diubah_oleh uuid,
  no_faktur text,
  tgl_faktur date,
  cash_minta boolean NOT NULL DEFAULT false,
  cash_ok boolean,
  cash_oleh uuid,
  cash_pada timestamp with time zone,
  kirim_ok boolean,
  kirim_ok_oleh uuid,
  kirim_ok_pada timestamp with time zone,
  kirim_alasan text,
  po_menyusul boolean NOT NULL DEFAULT false,
  po_menyusul_alasan text,
  po_menyusul_oleh uuid,
  po_menyusul_pada timestamp with time zone,
  tanpa_po_ok boolean NOT NULL DEFAULT false,
  tanpa_po_alasan text,
  tanpa_po_oleh uuid,
  tanpa_po_pada timestamp with time zone,
  vonny_ok boolean,
  vonny_oleh uuid,
  vonny_pada timestamp with time zone,
  vonny_alasan text,
  CONSTRAINT sales_orders_pkey PRIMARY KEY (id),
  CONSTRAINT sales_orders_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id),
  CONSTRAINT sales_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT sales_orders_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES public.quotes(id),
  CONSTRAINT sales_orders_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT sales_orders_gm_oleh_fkey FOREIGN KEY (gm_oleh) REFERENCES auth.users(id),
  CONSTRAINT sales_orders_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT sales_orders_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id),
  CONSTRAINT sales_orders_po_menyusul_oleh_fkey FOREIGN KEY (po_menyusul_oleh) REFERENCES auth.users(id),
  CONSTRAINT sales_orders_tanpa_po_oleh_fkey FOREIGN KEY (tanpa_po_oleh) REFERENCES auth.users(id),
  CONSTRAINT sales_orders_cash_oleh_fkey FOREIGN KEY (cash_oleh) REFERENCES auth.users(id),
  CONSTRAINT sales_orders_kirim_ok_oleh_fkey FOREIGN KEY (kirim_ok_oleh) REFERENCES auth.users(id)
);
-- status juga bisa 'menunggu vonny' (berkas 82): ada baris, vonny_ok bukan true, belum ada surat jalan.
-- Cek Vonny (#8): vonny_* hanya lewat RPC putuskan_vonny_cek (owner/gm/vonny); jaga_kolom_sales blok e2
--   menolak peran lain, kecuali pengguguran sistem (flag rhj.vonny_gugur, hanya mengosongkan) [berkas 86, 88].
-- Trigger so_status_dok (AFTER INSERT / UPDATE OF no_surat_jalan, no_invoice, no_faktur, lunas, batal,
--   harga_ok, vonny_ok, cash_ok, customer_id, sales_rep_id) -> so_sesudah_ubah() hitung ulang status [berkas 86].
-- Trigger so_vonny_gugur (AFTER UPDATE, WHEN customer_id/kepada/alamat/up/telp/ppn_kena/catatan berubah,
--   PO dilepas/diganti, atau po_menyusul/alasannya berganti pada SP tanpa PO) oleh selain owner/gm/vonny
--   -> gugurkan_cek_vonny(): vonny_ok/oleh/pada -> null selama barang belum keluar [berkas 88].
-- RPC tandai_sp_tanpa_po: selain owner/gm hanya PEMBUAT SP, sebelum cek Vonny & sebelum barang keluar [berkas 88].
-- Trigger so_jaga_pembuat (BEFORE UPDATE, WHEN dibuat_oleh/dibuat_pada berubah) [berkas 89]: hanya owner/gm.
-- Cash (#22): cash_minta = klaim sales, cash_ok = pencocokan (RPC cocokkan_cash_sp: owner/gm/finance/ichi;
--   trigger so_cash_jaga -> jaga_cash_sp mencatat cash_oleh/pada). Trigger so_x_cash_only (BEFORE INSERT OR
--   UPDATE OF sales_rep_id, cash_minta, cash_ok) -> jaga_cash_only() SECURITY DEFINER [berkas 95]: untuk SP rep
--   cash_only, cash_ok=false ditolak (juga di cocokkan_cash_sp), cash_minta true->false ditolak, INSERT / pindah
--   ke rep cash_only dipaksa cash_minta=true. Berlaku semua peran; nama "so_x_" = jalan sesudah so_pemilik.
-- Constraint trigger so_pelanggan_po (AFTER UPDATE OF customer_id, WHEN po_id terisi, DEFERRABLE INITIALLY
--   DEFERRED) [berkas 89] -> jaga_pelanggan_sp_po(): pelanggan SP = pelanggan PO-nya (dicek saat COMMIT).
-- RLS so_baca [berkas 83, 88]: sales pemilik; SP yang sedang dicek Vonny (tidak batal, belum surat jalan,
--   vonny_ok bukan true) hanya owner/gm/vonny + pembuatnya (dibuat_oleh, selama boleh_alur_jual);
--   selebihnya boleh_lihat_semua_jual().
CREATE TABLE public.sales_order_lines (
  id bigint NOT NULL DEFAULT nextval('sales_order_lines_id_seq'::regclass),
  so_id bigint NOT NULL,
  urut integer NOT NULL DEFAULT 1,
  product_id bigint,
  deskripsi text,
  qty numeric NOT NULL CHECK (qty > 0::numeric),
  harga_nett numeric NOT NULL,
  harga_list numeric,
  ehc_item numeric NOT NULL DEFAULT 0,
  jenis text NOT NULL DEFAULT 'barang'::text CHECK (jenis = ANY (ARRAY['barang'::text, 'biaya'::text])),
  batal boolean NOT NULL DEFAULT false, batal_alasan text, batal_oleh uuid, batal_pada timestamptz,
  qty_batal numeric(14,2) NOT NULL DEFAULT 0,   -- #18 berkas 98: qty dibatalkan (kumulatif); qty efektif = qty - qty_batal
                                                 --   backfill dari batal lama (98 (2b) / 102): qty_batal = qty - terkirim, catatan '[migrasi] …' di batal_alasan
  CONSTRAINT sol_qty_batal_sah CHECK (qty_batal >= 0 AND qty_batal <= qty),
  CONSTRAINT sales_order_lines_pkey PRIMARY KEY (id),
  CONSTRAINT sales_order_lines_so_id_fkey FOREIGN KEY (so_id) REFERENCES public.sales_orders(id),
  CONSTRAINT sales_order_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
-- Kolom batal/batal_alasan/batal_oleh/batal_pada (#18): lewat RPC batalkan_baris_sp / pulihkan_baris_sp.
-- Trigger sol_jaga_tambah (BEFORE INSERT) [berkas 88]: selain owner/gm (atau rhj.usul), baris baru hanya
--   selama SP segar (tidak batal, vonny_ok & harga_ok null, belum surat jalan/so_kirim/invoice).
-- Trigger sol_vonny_gugur (AFTER INSERT/UPDATE/DELETE) [berkas 88]: perubahan produk/qty/harga_nett/
--   ehc_item/jenis/deskripsi/batal/qty_batal oleh selain owner/gm/vonny -> gugurkan_cek_vonny(so_id).
-- #18 [berkas 98]: batal SISA qty per baris. batalkan_baris_sp(p_line, p_alasan, p_qty default null = seluruh
--   sisa) / pulihkan_baris_sp(p_line, p_qty default null = semua) — owner/gm/staff/vonny/sales pemilik; tolak
--   bila SP batal/ber-invoice/sudah terkirim semua (batal) atau ada klaim EHC/komisi. Qty terkirim TIDAK bisa
--   dibatalkan (maks = qty - qty_batal - terkirim). Menghabiskan seluruh barang (belum ada kiriman) -> SP ikut
--   batal lewat batalkan_sp (vonny ditolak). Sesudahnya finalisasi_kirim_sp. batal_alasan = log bertumpuk
--   "DD/MM/YYYY batal N: alasan" / "... pulih N".
-- Trigger sol_qty_batal (BEFORE INSERT/UPDATE) -> jaga_qty_batal_baris(): qty_batal/batal hanya lewat RPC
--   (flag rhj.batal_baris); qty tak bisa diubah selama ada qty_batal; qty efektif >= terkirim; batal := batal
--   penuh (qty_batal >= qty, kompatibel dengan penanda lama).
-- Trigger sol_jaga_hapus (BEFORE DELETE) -> jaga_hapus_baris_sp(): baris yang ada di surat jalan atau punya
--   qty_batal tidak bisa dihapus/diganti (putuskan_ubah) — kecuali cascade hapus SP.
-- View so_baris_hitung [berkas 98]: qty = qty EFEKTIF, nilai_* dari qty efektif, baris batal penuh dibuang;
--   kolom tambahan qty_pesan, qty_batal. so_ringkas/komisi/EHC/invoice/laporan_penjualan ikut efektif.
-- View sp_nilai_batal [berkas 98]: per SP grand_total_awal (semua qty, = periksa_total_sp), grand_total_efektif
--   (= so_ringkas.grand_total), nilai_batal, qty_batal_total, ada_batal.
-- View po_batal_ringkas [berkas 98]: per PO jml_sp, nilai_batal, grand_total_po, grand_total_efektif,
--   batal_sebagian. Invarian SP = PO dibandingkan pada NILAI AWAL (periksa_total_sp, sp_beda_po.total_sp,
--   sp_selisih_po); sp_beda_po punya kolom tambahan total_sp_efektif. PO sendiri tidak diubah.
-- #18 [berkas 100]: sales_orders.batal_karena_barang boolean default false = SP batal karena seluruh barangnya
--   dibatalkan customer lewat batalkan_baris_sp (bukan batalkan_sp biasa). Jalur itu juga menandai PO batal
--   (alasan "Semua barang dibatalkan customer (SP ..)") bila PO tak punya SP lain yang berlaku.
--   po_batal_ringkas ikut menghitung SP batal_karena_barang (nilai_batal = nilai awal SP, efektif 0) + kolom
--   batal_semua. po_belum_sp mengecualikan PO yang SP-nya batal_karena_barang. batalkan_sp biasa: PO tetap
--   kembali ke antrean (SP salah input dibuat ulang).
-- laporan_margin_produk / laporan_margin_sp / gm_konteks_keputusan memakai qty efektif [berkas 98].
-- #12 [berkas 106] RUPIAH BERSEN, TANPA PEMBULATAN: po_ringkas, so_baris_hitung, so_ringkas, sp_nilai_batal,
--   cash_belum_cocok, komisi_hitung, laporan_margin_* menghitung presisi penuh (numeric eksak; PPN = dasar × 0,11
--   tidak dibulatkan, komisi = nilai × pct tidak dibulatkan). "SP = PO" = sama SAMPAI SEN:
--   round(sp,2) <> round(po,2) → tolak (periksa_total_sp, tautkan_po_sp, sp_beda_po); round() hanya di pembanding.
--   ajukan_klaim_ehc: nominal dibanding EHC sampai sen. Fungsi rp_teks(numeric) → 'Rp 1.234,56' (lepas dari
--   lc_numeric) untuk pesan galat & keterangan antrean_gm. Kolom/tipe view tidak berubah; security_invoker tetap on.
--   Sengaja dibiarkan: isi_nilai_* round(x,2) (= presisi kolom numeric(18,2)), hitung_edit_massal (opsi
--   pembulatan pilihan pengguna), round(…,1) margin_pct (persen).
-- #10 [berkas 103]: view sp_menunggu_po (security_invoker) + kolom di ujung: po_menyusul, tanpa_po_alasan,
--   dibuat_oleh, vonny_ok, mode_po ('tanpa_po' | 'menyusul' | 'belum' = mode PO belum dinyatakan).
-- #21 [berkas 104]: gm_konteks_keputusan(p_jenis, p_ref) kini juga untuk 'ehc_dini' (ref = SP) dan 'ubah'
--   (ref = usul_ubah.id; baris versi 'sebelum'/'sesudah'). Hasil: kode, qty (efektif), harga_nett, ehc, hpp,
--   margin (= nett − HPP, sesudah EHC; NULL bila HPP kosong), harga_jual (= nett + EHC), margin_kotor
--   (= harga_jual − HPP, sebelum EHC), margin_pct, margin_total (= margin × qty), versi, urut. Baris batal
--   disaring. Untuk usul PO: harga_jual = harga efektif sesudah diskon, margin_kotor = harga_jual − HPP.
CREATE TABLE public.so_kirim (   -- surat jalan bertahap (#15, berkas 76)
  id bigint NOT NULL DEFAULT nextval('so_kirim_id_seq'::regclass),
  so_id bigint NOT NULL,
  no_surat_jalan text NOT NULL,
  tgl date NOT NULL,
  catatan text,
  dibuat_oleh uuid DEFAULT auth.uid(),
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT so_kirim_pkey PRIMARY KEY (id),
  CONSTRAINT so_kirim_so_id_fkey FOREIGN KEY (so_id) REFERENCES public.sales_orders(id)
);
CREATE TABLE public.so_kirim_baris (
  id bigint NOT NULL DEFAULT nextval('so_kirim_baris_id_seq'::regclass),
  kirim_id bigint NOT NULL,
  so_line_id bigint NOT NULL,
  qty numeric NOT NULL CHECK (qty > 0::numeric),
  CONSTRAINT so_kirim_baris_pkey PRIMARY KEY (id),
  CONSTRAINT so_kirim_baris_kirim_id_fkey FOREIGN KEY (kirim_id) REFERENCES public.so_kirim(id) ON DELETE CASCADE,
  CONSTRAINT so_kirim_baris_so_line_id_fkey FOREIGN KEY (so_line_id) REFERENCES public.sales_order_lines(id)
);
-- View so_kirim_sisa (per baris barang aktif: qty_pesan, qty_kirim, sisa = qty - qty_batal - terkirim,
--   qty_batal, qty_efektif [berkas 98]). Tulis HANYA lewat RPC tambah_surat_jalan / batal_surat_jalan
--   (owner/gm/liesian) yang menyalakan flag rhj.kirim.
-- RLS/grant [berkas 97]: policy sokirim_tulis/sokirimb_tulis dihapus; anon tanpa akses; authenticated hanya
--   SELECT pada so_kirim, so_kirim_baris, so_kirim_sisa, so_kirim_ringkas.
-- gerbang_kirim_sp(p_so) [berkas 97, internal]: gerbang SETIAP surat jalan (batal, draft, vonny_ok, kirim_ok,
--   gerbang 1/2/3a cermin jaga_urutan_dokumen_sp — ubah keduanya bersama). Dipanggil tambah_surat_jalan &
--   trigger jaga_so_kirim.
-- finalisasi_kirim_sp(p_so) [berkas 97/99, internal]: bila ada so_kirim & semua sisa 0 -> no_surat_jalan/tgl =
--   batch terakhir; bila sisa > 0 lagi -> dilepas (ditolak bila ber-invoice). Menyalakan rhj.kirim + rhj.sj_final
--   (jaga_kolom_sales blok a melewatkan kolom surat jalan selama flag ini). Dipakai tambah_surat_jalan,
--   batalkan_baris_sp, pulihkan_baris_sp.
-- Trigger so_kirim_jaga & so_kirim_baris_jaga (BEFORE INSERT/UPDATE/DELETE) [berkas 89]: tanpa rhj.kirim
--   ditolak (termasuk owner); so_kirim baru wajib SP tidak batal, vonny_ok = true, kirim_ok bukan false,
--   status_sp_hitung bukan menunggu gm/menunggu vonny/draft; baris wajib barang aktif SP itu & qty <= sisa.
-- tambah_surat_jalan [berkas 89]: kunci SP (FOR UPDATE), pakai status_sp_hitung, tolak SP yang sudah
--   ber-invoice atau sudah dikirim sekaligus (no_surat_jalan kepala terisi tanpa so_kirim).
CREATE TABLE public.customer_pics (
  id bigint NOT NULL DEFAULT nextval('customer_pics_id_seq'::regclass),
  customer_id bigint,
  nama text NOT NULL,
  jabatan text,
  hp text,
  bank text,
  no_rekening text,
  atas_nama text,
  terkunci boolean NOT NULL DEFAULT false,
  aktif boolean NOT NULL DEFAULT true,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  CONSTRAINT customer_pics_pkey PRIMARY KEY (id),
  CONSTRAINT customer_pics_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT customer_pics_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.pic_rekening_ubah (
  id bigint NOT NULL DEFAULT nextval('pic_rekening_ubah_id_seq'::regclass),
  pic_id bigint NOT NULL,
  lama_bank text,
  lama_no_rekening text,
  lama_atas_nama text,
  bank text NOT NULL,
  no_rekening text NOT NULL,
  atas_nama text,
  alasan text NOT NULL CHECK (btrim(alasan) <> ''::text),
  status text NOT NULL DEFAULT 'menunggu'::text CHECK (status = ANY (ARRAY['menunggu'::text, 'disetujui'::text, 'ditolak'::text])),
  diajukan_oleh uuid,
  diajukan_pada timestamp with time zone NOT NULL DEFAULT now(),
  diputus_oleh uuid,
  diputus_pada timestamp with time zone,
  CONSTRAINT pic_rekening_ubah_pkey PRIMARY KEY (id),
  CONSTRAINT pic_rekening_ubah_pic_id_fkey FOREIGN KEY (pic_id) REFERENCES public.customer_pics(id),
  CONSTRAINT pic_rekening_ubah_diajukan_oleh_fkey FOREIGN KEY (diajukan_oleh) REFERENCES auth.users(id),
  CONSTRAINT pic_rekening_ubah_diputus_oleh_fkey FOREIGN KEY (diputus_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.ehc_klaim (
  id bigint NOT NULL DEFAULT nextval('ehc_klaim_id_seq'::regclass),
  so_id bigint NOT NULL,
  pic_id bigint,
  sales_rep_id bigint,
  bank text,
  no_rekening text,
  atas_nama text,
  dini boolean NOT NULL DEFAULT false,
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  cara_bayar text NOT NULL DEFAULT 'transfer'::text CHECK (cara_bayar = ANY (ARRAY['transfer'::text, 'tunai'::text])),
  transfer_batch_id bigint,
  cepat_minta boolean NOT NULL DEFAULT false,
  cepat_alasan text,
  cepat_ok boolean,
  cepat_catatan text,
  cepat_diminta_oleh uuid,
  cepat_diminta_pada timestamp with time zone,
  cepat_diputus_oleh uuid,
  cepat_diputus_pada timestamp with time zone,
  CONSTRAINT ehc_klaim_pkey PRIMARY KEY (id),
  CONSTRAINT ehc_klaim_so_id_fkey FOREIGN KEY (so_id) REFERENCES public.sales_orders(id),
  CONSTRAINT ehc_klaim_pic_id_fkey FOREIGN KEY (pic_id) REFERENCES public.customer_pics(id),
  CONSTRAINT ehc_klaim_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT ehc_klaim_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT ehc_klaim_transfer_batch_id_fkey FOREIGN KEY (transfer_batch_id) REFERENCES public.transfer_batch(id),
  CONSTRAINT ehc_klaim_cepat_diminta_oleh_fkey FOREIGN KEY (cepat_diminta_oleh) REFERENCES auth.users(id),
  CONSTRAINT ehc_klaim_cepat_diputus_oleh_fkey FOREIGN KEY (cepat_diputus_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.ehc_klaim_nilai (
  klaim_id bigint NOT NULL,
  nominal numeric NOT NULL,
  kas numeric NOT NULL DEFAULT 0,
  CONSTRAINT ehc_klaim_nilai_pkey PRIMARY KEY (klaim_id),
  CONSTRAINT ehc_klaim_nilai_klaim_id_fkey FOREIGN KEY (klaim_id) REFERENCES public.ehc_klaim(id)
);
CREATE TABLE public.ehc_klaim_berkas (
  id bigint NOT NULL DEFAULT nextval('ehc_klaim_berkas_id_seq'::regclass),
  klaim_id bigint NOT NULL,
  nama_berkas text NOT NULL CHECK (btrim(nama_berkas) <> ''::text),
  path text NOT NULL CHECK (btrim(path) <> ''::text),
  ukuran bigint,
  mime text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  CONSTRAINT ehc_klaim_berkas_pkey PRIMARY KEY (id),
  CONSTRAINT ehc_klaim_berkas_klaim_id_fkey FOREIGN KEY (klaim_id) REFERENCES public.ehc_klaim(id),
  CONSTRAINT ehc_klaim_berkas_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.sales_rep_rekening (
  sales_rep_id bigint NOT NULL,
  bank text NOT NULL CHECK (btrim(bank) <> ''::text),
  no_rekening text NOT NULL CHECK (btrim(no_rekening) <> ''::text),
  atas_nama text,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  CONSTRAINT sales_rep_rekening_pkey PRIMARY KEY (sales_rep_id),
  CONSTRAINT sales_rep_rekening_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT sales_rep_rekening_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.sales_rep_rekening_log (
  id bigint NOT NULL DEFAULT nextval('sales_rep_rekening_log_id_seq'::regclass),
  sales_rep_id bigint NOT NULL,
  lama_bank text,
  lama_no_rekening text,
  lama_atas_nama text,
  bank text,
  no_rekening text,
  atas_nama text,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  CONSTRAINT sales_rep_rekening_log_pkey PRIMARY KEY (id),
  CONSTRAINT sales_rep_rekening_log_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT sales_rep_rekening_log_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.komisi_klaim (
  id bigint NOT NULL DEFAULT nextval('komisi_klaim_id_seq'::regclass),
  so_id bigint NOT NULL,
  sales_rep_id bigint,
  bank text,
  no_rekening text,
  atas_nama text,
  telat boolean NOT NULL DEFAULT false,
  pct_gm numeric,
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  transfer_batch_id bigint,
  CONSTRAINT komisi_klaim_pkey PRIMARY KEY (id),
  CONSTRAINT komisi_klaim_so_id_fkey FOREIGN KEY (so_id) REFERENCES public.sales_orders(id),
  CONSTRAINT komisi_klaim_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id),
  CONSTRAINT komisi_klaim_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id),
  CONSTRAINT komisi_klaim_transfer_batch_id_fkey FOREIGN KEY (transfer_batch_id) REFERENCES public.transfer_batch(id)
);
CREATE TABLE public.komisi_klaim_nilai (
  klaim_id bigint NOT NULL,
  nominal numeric NOT NULL CHECK (nominal >= 0::numeric),
  CONSTRAINT komisi_klaim_nilai_pkey PRIMARY KEY (klaim_id),
  CONSTRAINT komisi_klaim_nilai_klaim_id_fkey FOREIGN KEY (klaim_id) REFERENCES public.komisi_klaim(id)
);
CREATE TABLE public.komisi_klaim_berkas (
  id bigint NOT NULL DEFAULT nextval('komisi_klaim_berkas_id_seq'::regclass),
  klaim_id bigint NOT NULL,
  nama_berkas text NOT NULL CHECK (btrim(nama_berkas) <> ''::text),
  path text NOT NULL CHECK (btrim(path) <> ''::text),
  ukuran bigint,
  mime text,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  dibuat_oleh uuid,
  CONSTRAINT komisi_klaim_berkas_pkey PRIMARY KEY (id),
  CONSTRAINT komisi_klaim_berkas_klaim_id_fkey FOREIGN KEY (klaim_id) REFERENCES public.komisi_klaim(id),
  CONSTRAINT komisi_klaim_berkas_dibuat_oleh_fkey FOREIGN KEY (dibuat_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.harga_khusus (
  id bigint NOT NULL DEFAULT nextval('harga_khusus_id_seq'::regclass),
  customer_id bigint NOT NULL,
  product_id bigint NOT NULL,
  harga_nett numeric NOT NULL,
  ehc_item numeric NOT NULL DEFAULT 0,
  komisi_pct numeric CHECK (komisi_pct IS NULL OR komisi_pct >= 0::numeric AND komisi_pct <= 0.5),
  status text NOT NULL DEFAULT 'menunggu'::text CHECK (status = ANY (ARRAY['menunggu'::text, 'aktif'::text, 'ditolak'::text, 'nonaktif'::text])),
  alasan text,
  catatan_gm text,
  so_id bigint,
  diajukan_oleh uuid,
  diajukan_pada timestamp with time zone NOT NULL DEFAULT now(),
  diputus_oleh uuid,
  diputus_pada timestamp with time zone,
  CONSTRAINT harga_khusus_pkey PRIMARY KEY (id),
  CONSTRAINT harga_khusus_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT harga_khusus_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT harga_khusus_so_id_fkey FOREIGN KEY (so_id) REFERENCES public.sales_orders(id),
  CONSTRAINT harga_khusus_diajukan_oleh_fkey FOREIGN KEY (diajukan_oleh) REFERENCES auth.users(id),
  CONSTRAINT harga_khusus_diputus_oleh_fkey FOREIGN KEY (diputus_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.harga_khusus_log (
  id bigint NOT NULL DEFAULT nextval('harga_khusus_log_id_seq'::regclass),
  harga_khusus_id bigint NOT NULL,
  lama_harga numeric,
  lama_ehc numeric,
  lama_pct numeric,
  lama_status text,
  harga_nett numeric,
  ehc_item numeric,
  komisi_pct numeric,
  status text,
  catatan text,
  diubah_pada timestamp with time zone NOT NULL DEFAULT now(),
  diubah_oleh uuid,
  CONSTRAINT harga_khusus_log_pkey PRIMARY KEY (id),
  CONSTRAINT harga_khusus_log_harga_khusus_id_fkey FOREIGN KEY (harga_khusus_id) REFERENCES public.harga_khusus(id),
  CONSTRAINT harga_khusus_log_diubah_oleh_fkey FOREIGN KEY (diubah_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.transfer_batch (
  id bigint NOT NULL DEFAULT nextval('transfer_batch_id_seq'::regclass),
  jenis text NOT NULL CHECK (jenis = ANY (ARRAY['ehc'::text, 'komisi'::text])),
  bulan text NOT NULL CHECK (bulan ~ '^\d{4}-\d{2}$'::text),
  tanggal date NOT NULL DEFAULT CURRENT_DATE,
  jumlah_klaim integer NOT NULL DEFAULT 0,
  total numeric NOT NULL DEFAULT 0,
  no_referensi text,
  catatan text,
  dibuat_oleh uuid,
  dibuat_pada timestamp with time zone NOT NULL DEFAULT now(),
  ref_oleh uuid,
  ref_pada timestamp with time zone,
  cepat boolean NOT NULL DEFAULT false,
  CONSTRAINT transfer_batch_pkey PRIMARY KEY (id)
);
CREATE TABLE public.usul_ubah (
  id bigint NOT NULL DEFAULT nextval('usul_ubah_id_seq'::regclass),
  jenis text NOT NULL CHECK (jenis = ANY (ARRAY['po'::text, 'sp'::text])),
  ref_id bigint NOT NULL,
  nilai_lama jsonb NOT NULL,
  nilai_baru jsonb NOT NULL,
  alasan text NOT NULL CHECK (length(btrim(alasan)) >= 5),
  status text NOT NULL DEFAULT 'menunggu'::text CHECK (status = ANY (ARRAY['menunggu'::text, 'disetujui'::text, 'ditolak'::text])),
  catatan_gm text,
  diajukan_oleh uuid,
  diajukan_pada timestamp with time zone NOT NULL DEFAULT now(),
  diputus_oleh uuid,
  diputus_pada timestamp with time zone,
  CONSTRAINT usul_ubah_pkey PRIMARY KEY (id)
);
-- Indeks unik uu_menunggu_uniq (jenis, ref_id) WHERE status = 'menunggu' → satu usulan menunggu per dokumen.
-- Tulis hanya lewat RPC ajukan_ubah / putuskan_ubah (SECURITY DEFINER). Sales hanya boleh mengajukan untuk
--   PO/SP miliknya (sales_rep_id = sales_rep_saya()) [cabang po: berkas 96].
-- RLS uu_baca (berkas 96): setara_owner() OR dokumennya terbaca oleh pembaca (EXISTS ke purchase_orders /
--   sales_orders, tunduk RLS po_baca / so_baca) → usulan atas SP menunggu Vonny ikut tersembunyi seperti SP-nya.
CREATE TABLE public.edit_massal_timpa (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  batch_id bigint NOT NULL,
  jenis text NOT NULL CHECK (jenis = ANY (ARRAY['harga'::text, 'hpp'::text])),
  product_id bigint NOT NULL,
  berlaku_dari date NOT NULL,
  nilai_lama numeric NOT NULL,
  catatan_lama text,
  sumber_lama text,
  batch_lama bigint,
  dibuat_oleh_lama uuid,
  dibuat_pada_lama timestamp with time zone,
  CONSTRAINT edit_massal_timpa_pkey PRIMARY KEY (id),
  CONSTRAINT edit_massal_timpa_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.edit_massal(id)
);
CREATE TABLE public.tautan_sales_batch (
  id bigint NOT NULL DEFAULT nextval('tautan_sales_batch_id_seq'::regclass),
  dijalankan_pada timestamp with time zone NOT NULL DEFAULT now(),
  oleh uuid,
  jumlah integer NOT NULL DEFAULT 0,
  catatan text,
  CONSTRAINT tautan_sales_batch_pkey PRIMARY KEY (id),
  CONSTRAINT tautan_sales_batch_oleh_fkey FOREIGN KEY (oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.tautan_sales_baris (
  batch_id bigint NOT NULL,
  customer_id bigint NOT NULL,
  sales_rep_id bigint NOT NULL,
  CONSTRAINT tautan_sales_baris_pkey PRIMARY KEY (batch_id, customer_id),
  CONSTRAINT tautan_sales_baris_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.tautan_sales_batch(id),
  CONSTRAINT tautan_sales_baris_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT tautan_sales_baris_sales_rep_id_fkey FOREIGN KEY (sales_rep_id) REFERENCES public.sales_reps(id)
);
CREATE TABLE public.ubah_sales_batch (
  id bigint NOT NULL DEFAULT nextval('ubah_sales_batch_id_seq'::regclass),
  jenis text NOT NULL,
  dijalankan_pada timestamp with time zone NOT NULL DEFAULT now(),
  oleh uuid,
  jumlah integer NOT NULL DEFAULT 0,
  catatan text,
  CONSTRAINT ubah_sales_batch_pkey PRIMARY KEY (id),
  CONSTRAINT ubah_sales_batch_oleh_fkey FOREIGN KEY (oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.ubah_sales_baris (
  id bigint NOT NULL DEFAULT nextval('ubah_sales_baris_id_seq'::regclass),
  batch_id bigint NOT NULL,
  tabel text NOT NULL,
  baris_id bigint NOT NULL,
  rep_lama bigint,
  rep_baru bigint,
  aktif_lama boolean,
  aktif_baru boolean,
  CONSTRAINT ubah_sales_baris_pkey PRIMARY KEY (id),
  CONSTRAINT ubah_sales_baris_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.ubah_sales_batch(id)
);
CREATE TABLE public.transfer_pengajuan (
  id bigint NOT NULL DEFAULT nextval('transfer_pengajuan_id_seq'::regclass),
  jenis text NOT NULL CHECK (jenis = ANY (ARRAY['ehc'::text, 'komisi'::text])),
  bulan text NOT NULL CHECK (bulan ~ '^\d{4}-\d{2}$'::text),
  status text NOT NULL DEFAULT 'menunggu'::text CHECK (status = ANY (ARRAY['menunggu'::text, 'disetujui'::text, 'ditolak'::text, 'selesai'::text])),
  jumlah_klaim integer NOT NULL DEFAULT 0,
  total numeric NOT NULL DEFAULT 0,
  catatan text,
  catatan_gm text,
  diajukan_oleh uuid,
  diajukan_pada timestamp with time zone NOT NULL DEFAULT now(),
  diputus_oleh uuid,
  diputus_pada timestamp with time zone,
  transfer_batch_id bigint,
  CONSTRAINT transfer_pengajuan_pkey PRIMARY KEY (id),
  CONSTRAINT transfer_pengajuan_diputus_oleh_fkey FOREIGN KEY (diputus_oleh) REFERENCES auth.users(id),
  CONSTRAINT transfer_pengajuan_transfer_batch_id_fkey FOREIGN KEY (transfer_batch_id) REFERENCES public.transfer_batch(id),
  CONSTRAINT transfer_pengajuan_diajukan_oleh_fkey FOREIGN KEY (diajukan_oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.transfer_pengajuan_baris (
  pengajuan_id bigint NOT NULL,
  klaim_id bigint NOT NULL,
  CONSTRAINT transfer_pengajuan_baris_pkey PRIMARY KEY (pengajuan_id, klaim_id),
  CONSTRAINT transfer_pengajuan_baris_pengajuan_id_fkey FOREIGN KEY (pengajuan_id) REFERENCES public.transfer_pengajuan(id)
);
CREATE TABLE public.ehc_cepat_log (
  id bigint NOT NULL DEFAULT nextval('ehc_cepat_log_id_seq'::regclass),
  klaim_id bigint NOT NULL,
  aksi text NOT NULL CHECK (aksi = ANY (ARRAY['minta'::text, 'tarik'::text, 'setuju'::text, 'tolak'::text])),
  alasan text,
  oleh uuid,
  pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ehc_cepat_log_pkey PRIMARY KEY (id),
  CONSTRAINT ehc_cepat_log_klaim_id_fkey FOREIGN KEY (klaim_id) REFERENCES public.ehc_klaim(id),
  CONSTRAINT ehc_cepat_log_oleh_fkey FOREIGN KEY (oleh) REFERENCES auth.users(id)
);
CREATE TABLE public.hak_fungsi_sebelum_52 (
  sig text NOT NULL,
  public_boleh boolean NOT NULL,
  anon_boleh boolean NOT NULL,
  auth_boleh boolean NOT NULL,
  dicatat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT hak_fungsi_sebelum_52_pkey PRIMARY KEY (sig)
);
CREATE TABLE public.view_sebelum_57 (
  nama text NOT NULL,
  def text NOT NULL,
  dicatat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT view_sebelum_57_pkey PRIMARY KEY (nama)
);
CREATE TABLE public.customers_nama_sebelum_100 (   -- [berkas 100, #20] cadangan nama sebelum dirapikan (RLS, tanpa akses klien)
  id bigint NOT NULL,
  nama text NOT NULL,
  nama_lama text,
  diubah_oleh uuid,
  diubah_pada timestamp with time zone,
  dicatat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT customers_nama_sebelum_100_pkey PRIMARY KEY (id)
);
CREATE TABLE public.customers_industri_sebelum_101 (   -- [berkas 101, #25] cadangan industri sebelum diisi dari industri_lama
  id bigint NOT NULL,
  industri text,
  industri_lama text,
  industri_baru text NOT NULL,
  diubah_oleh uuid,
  diubah_pada timestamp with time zone,
  dicatat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT customers_industri_sebelum_101_pkey PRIMARY KEY (id)
);
CREATE TABLE public.customers_industri_koreksi_105 (   -- [berkas 105, #25] isian otomatis 101 yang dikoreksi (kata generik supplier/trading/toko/… → NULL); RLS aktif, tanpa akses klien
  id bigint NOT NULL,
  industri_lama text,
  industri_sebelum text,
  industri_sesudah text,
  dicatat_pada timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT customers_industri_koreksi_105_pkey PRIMARY KEY (id)
);
