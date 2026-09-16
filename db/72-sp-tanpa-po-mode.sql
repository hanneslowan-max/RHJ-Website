-- Berkas 72 (#10): mode SP ke-3 "tanpa PO sama sekali" — TANPA perlu owner/GM.
--
-- Konteks 3 mode SP (keputusan Hannes):
--   1) PO di depan  : SP dibuat dari PO (po_id terisi).
--   2) PO menyusul  : barang berangkat dulu; invoice DITAHAN sampai PO ditempelkan.
--   3) tanpa PO      : pelanggan memang tak menerbitkan PO; invoice BOLEH terbit tanpa PO.
--      → mode 3 tidak perlu GM; kontrolnya cek Vonny (#8) yang tetap wajib sebelum surat jalan.
--
-- Kolom sudah ada (pra-berkas): sales_orders.tanpa_po_ok/_alasan/_oleh/_pada, po_menyusul*.
-- Gerbang lama (jaga_urutan_dokumen_sp): surat jalan tanpa PO butuh po_menyusul ATAU tanpa_po_ok;
--   invoice tanpa PO butuh tanpa_po_ok. Gerbang Vonny (jaga_gerbang_vonny, berkas 67) memblok
--   no_surat_jalan untuk SEMUA SP sampai vonny_ok=true → itulah kontrol mode "tanpa PO".
-- Trigger jaga_po_menyusul melarang tanpa_po_ok diisi langsung; hanya lewat pintu ber-set_config.
--   izinkan_invoice_tanpa_po() lama = pintu owner/GM (tetap dipertahankan untuk kasus darurat).
--   RPC ini = pintu ke-2 untuk PEMBUAT SP (owner/gm/staff/sales/vonny), sales hanya utk SP miliknya.
--
-- FE (index.html): dropdown "Sumber" di form SP dapat opsi ke-3 "Tanpa PO sama sekali — cukup cek
--   Vonny". Mode manual (ketik baris) dipakai bersama "PO menyusul" via helper spManual(f).
--   Saat simpan: SP di-INSERT dulu (tanpa_po_ok=false, legal karena belum ada surat jalan),
--   lalu dipanggil tandai_sp_tanpa_po() untuk menyalakan tanpa_po_ok.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

create or replace function public.tandai_sp_tanpa_po(p_so bigint, p_alasan text)
returns text language plpgsql security definer set search_path=public as $$
declare v record;
begin
  if not public.boleh_input_po() then
    raise exception 'Anda tidak berhak membuat Surat Pesanan.' using errcode='42501';
  end if;
  if coalesce(btrim(p_alasan),'') = '' then
    raise exception 'Mode tanpa PO wajib beralasan (mis. pelanggan tidak menerbitkan PO / order lisan).'
      using errcode='22023';
  end if;
  select * into v from public.sales_orders where id = p_so;
  if v.id is null then
    raise exception 'Surat Pesanan #% tidak ditemukan.', p_so using errcode='P0002';
  end if;
  if not (public.setara_owner() or public.peran_saya() in ('staff','vonny')
          or v.sales_rep_id = public.sales_rep_saya()) then
    raise exception 'Surat Pesanan % milik sales lain — tidak bisa Anda tandai.', v.no_sp
      using errcode='42501';
  end if;
  if v.po_id is not null then
    raise exception 'Surat Pesanan % sudah punya PO — tidak perlu mode tanpa PO.', v.no_sp
      using errcode='22023';
  end if;

  perform set_config('rhj.tanpa_po','1',true);
  update public.sales_orders
     set tanpa_po_ok    = true,
         tanpa_po_alasan= btrim(p_alasan),
         tanpa_po_oleh  = coalesce(tanpa_po_oleh, auth.uid()),
         tanpa_po_pada  = coalesce(tanpa_po_pada, now()),
         po_menyusul    = false,
         po_menyusul_alasan = null
   where id = p_so;
  perform set_config('rhj.tanpa_po','',true);

  return 'Surat Pesanan ' || v.no_sp || ' ditandai TANPA PO. Cek Vonny tetap wajib sebelum surat jalan.';
end $$;

grant execute on function public.tandai_sp_tanpa_po(bigint,text) to authenticated;
