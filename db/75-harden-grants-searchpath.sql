-- Berkas 75: pengerasan keamanan untuk fungsi berkas 71-73.
-- (a) REVOKE EXECUTE ... FROM public, anon pada 6 RPC SECURITY DEFINER baru (sisakan authenticated):
--     pratinjau_nama_pelanggan, terapkan_rapi_nama, pulihkan_nama_pelanggan,
--     tandai_sp_tanpa_po, batalkan_baris_sp, pulihkan_baris_sp.
--     Alasan: grant default PostgreSQL memberi EXECUTE ke PUBLIC (termasuk anon). Gerbang internal
--     (boleh_*) sudah menolak anon (auth.uid() null), tapi ini menyamakan postur dengan fungsi lain
--     yang memang tidak anon-callable (Supabase linter 0028).
-- (b) ALTER FUNCTION rhj_nama_rapi(text) SET search_path=public (linter 0011; konsistensi).
--     rhj_nama_rapi SECURITY INVOKER + murni (format teks) → tetap boleh anon, tak mengekspos apa pun.
-- Diverifikasi: has_function_privilege('anon',...,'execute') = false utk ke-6 RPC; authenticated = true.
-- Diterapkan ke DEV (eesdtbcualkdawhykchj) 15 Sep 2026. Belum ke produksi.

revoke execute on function public.pratinjau_nama_pelanggan()          from public, anon;
revoke execute on function public.terapkan_rapi_nama(bigint[])        from public, anon;
revoke execute on function public.pulihkan_nama_pelanggan(bigint[])   from public, anon;
revoke execute on function public.tandai_sp_tanpa_po(bigint, text)    from public, anon;
revoke execute on function public.batalkan_baris_sp(bigint, text)     from public, anon;
revoke execute on function public.pulihkan_baris_sp(bigint)           from public, anon;

alter function public.rhj_nama_rapi(text) set search_path = public;
