CREATE OR REPLACE FUNCTION public.buat_profil_baru()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare email_owner constant text := 'palletmeshindonesia@gmail.com';
begin
  insert into public.profiles (id, email, nama, peran)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'full_name',
                   new.raw_user_meta_data->>'name', new.email),
          case when lower(coalesce(new.email,'')) = lower(email_owner)
               then 'owner' else 'pending' end)
  on conflict (id) do nothing;
  return new;
end $function$;
