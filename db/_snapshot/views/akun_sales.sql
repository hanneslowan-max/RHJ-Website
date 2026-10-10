-- reloptions: (none)
create or replace view public.akun_sales as
 SELECT sales_rep_id,
    sales_nama,
    jenis,
    aktif,
    profile_id,
    profil_email,
    profil_peran
   FROM ( SELECT r.id AS sales_rep_id,
            r.nama AS sales_nama,
            r.jenis,
            r.aktif,
            r.profile_id,
            p.email AS profil_email,
            p.peran AS profil_peran
           FROM sales_reps r
             LEFT JOIN profiles p ON p.id = r.profile_id) v
  WHERE boleh_baca();
