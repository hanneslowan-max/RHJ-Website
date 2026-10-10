CREATE OR REPLACE FUNCTION public.customers_jaga_sales()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.sales_rep_id is distinct from old.sales_rep_id
     and public.peran_saya() = 'sales' then
    -- Sales boleh MENGAKUI pelanggan yang belum bertuan, dan hanya untuk
    -- dirinya sendiri. Selebihnya keputusan atasan.
    if old.sales_rep_id is not null then
      raise exception 'Pelanggan ini sudah dipegang sales lain. Pemindahan pelanggan '
                      'diputuskan owner, GM, atau staff — bukan diambil sendiri.'
        using errcode = 'P0001';
    end if;
    if new.sales_rep_id is distinct from public.sales_rep_saya() then
      raise exception 'Anda hanya bisa mengambil pelanggan yang belum bertuan untuk diri '
                      'sendiri.' using errcode = 'P0001';
    end if;
    -- 138 (keputusan Hannes 9 Okt no. 17a): hanya otomatis lewat PO (po_auto_klaim_sales)
    if coalesce(current_setting('rhj.klaim_po', true), '') <> '1' then
      raise exception 'Pelanggan yang belum bertuan menjadi milik sales yang pertama membuat PO untuknya — tidak bisa '
                      'diambil langsung. Bila perlu dipindahkan sekarang, minta owner, GM, atau staff.';
    end if;
  end if;
  return new;
end $function$;
