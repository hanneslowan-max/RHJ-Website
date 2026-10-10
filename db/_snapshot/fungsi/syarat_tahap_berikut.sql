CREATE OR REPLACE FUNCTION public.syarat_tahap_berikut(p_order bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o record; kurang text[] := '{}'; n_kirim int; hilang text;
begin
  select status_produksi, no_proforma, no_do into o
    from public.orders where id = p_order;
  if not found then return null; end if;

  if o.status_produksi = 'Sudah Diterima' then return null; end if;

  if public.urutan_status(o.status_produksi) < 2 then
    if coalesce(btrim(o.no_proforma), '') = '' then
      kurang := array_append(kurang, 'nomor Proforma Invoice'); end if;
    if not exists (select 1 from public.documents
                    where order_id = p_order and jenis = 'Proforma Invoice') then
      kurang := array_append(kurang, 'lampiran Proforma Invoice'); end if;
    return 'Untuk naik ke Proses Produksi, yang belum ada: '
           || array_to_string(kurang, ', ') || '.';
  end if;

  if public.urutan_status(o.status_produksi) < 3 then
    select count(distinct jenis) into n_kirim from public.documents
     where order_id = p_order
       and jenis in ('Commercial Invoice','Packing List',
                     'Certificate of Origin','Bill of Lading');
    if n_kirim < 4 then
      select string_agg(j, ', ') into hilang from (
        select j from unnest(array['Commercial Invoice','Packing List',
                                   'Certificate of Origin','Bill of Lading']) j
        except select jenis from public.documents where order_id = p_order) x;
      return 'Untuk naik ke Dalam Pengiriman, dokumen yang belum ada: ' || hilang || '.';
    end if;
  end if;

  if public.urutan_status(o.status_produksi) < 4 then
    if coalesce(btrim(o.no_do), '') = '' then
      kurang := array_append(kurang, 'nomor Delivery Order'); end if;
    if not exists (select 1 from public.documents
                    where order_id = p_order and jenis = 'Delivery Order') then
      kurang := array_append(kurang, 'lampiran Delivery Order'); end if;
    if array_length(kurang, 1) is not null then
      return 'Untuk naik ke Proses Customs, yang belum ada: '
             || array_to_string(kurang, ', ') || '.';
    end if;
  end if;

  return 'Sudah di Proses Customs — tinggal tombol "Pesanan diterima".';
end $function$;
