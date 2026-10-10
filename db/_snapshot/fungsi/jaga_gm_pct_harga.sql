CREATE OR REPLACE FUNCTION public.jaga_gm_pct_harga()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or public.boleh_approve() then return new; end if;   -- sistem/migrasi, GM, owner
  if (tg_op = 'INSERT' and new.gm_pct_harga is not null)
     or (tg_op = 'UPDATE' and new.gm_pct_harga is distinct from old.gm_pct_harga) then
    raise exception 'Peran Anda (%) tidak boleh mengisi persentase komisi GM pada Surat Pesanan %. Kolom itu wewenang GM atau owner.',
      public.peran_saya(), coalesce(new.no_sp, '(baru)') using errcode = '42501';
  end if;
  return new;
end $function$;
