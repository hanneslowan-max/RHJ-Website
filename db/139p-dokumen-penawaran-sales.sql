-- ═══════════════════════════════════════════════════════════════════════
-- 139p · #55 (contoh penawaran dari Hannes 9 Okt — "040 PENAWARAN PT Zioflex Mandiri Indonesia"): data sales untuk
--        tanda tangan dokumen penawaran
-- (nomor 139p: jatah nomor sesi ini 120–139; "p" = penawaran, diurutkan sesudah 139k dan sebelum berkas EHC 140+.)
--
-- Template penawaran menutup dokumen dengan "Hormat kami," lalu nama lengkap sales beserta gelarnya (mis. "Riksa Sri
-- Gustiana,S.Sos"), No. HP, dan e-mail kantor (@rodahammerindo.com). Data itu belum ada: sales_reps.nama hanya nama
-- panggilan ("Riksa"), profiles.email adalah e-mail login pribadi, dan No. HP sales tidak tercatat di mana pun.
--
-- Perubahan:
--  · sales_reps + nama_dokumen, hp_dokumen, email_dokumen (boleh kosong — dokumen memakai nama sales & tanpa baris
--    HP/e-mail). Diisi owner/GM (RLS rep_tulis = setara_owner, tidak berubah) lewat tab Pengguna. Terbaca peran yang
--    sudah membaca sales_reps (rep_baca) — memang dicetak untuk customer.
--  · Dirapikan trigger: spasi tepi dibuang, kosong → NULL, e-mail huruf kecil, No. HP dibakukan (hp_baku, sama dengan
--    No. HP pelanggan). CHECK: nama ≤ 120 karakter, No. HP 9–16 angka, e-mail berbentuk nama@domain.
--  · Riksa diisi dari contoh penawaran Hannes (hanya bila masih kosong).
-- Tidak ada objek yang dibuang; data lain tidak berubah.
-- ═══════════════════════════════════════════════════════════════════════

alter table public.sales_reps add column if not exists nama_dokumen  text;
alter table public.sales_reps add column if not exists hp_dokumen    text;
alter table public.sales_reps add column if not exists email_dokumen text;
comment on column public.sales_reps.nama_dokumen  is '139p: nama lengkap + gelar di tanda tangan dokumen penawaran (kosong = nama).';
comment on column public.sales_reps.hp_dokumen    is '139p: No. HP sales di dokumen penawaran (dibakukan hp_baku).';
comment on column public.sales_reps.email_dokumen is '139p: e-mail kantor sales di dokumen penawaran.';

create or replace function public.sales_reps_dokumen_rapi()
returns trigger language plpgsql set search_path = public as $$
begin
  new.nama_dokumen  := nullif(btrim(coalesce(new.nama_dokumen, '')), '');
  new.hp_dokumen    := public.hp_baku(new.hp_dokumen);
  new.email_dokumen := nullif(lower(btrim(coalesce(new.email_dokumen, ''))), '');
  return new;
end $$;
revoke all on function public.sales_reps_dokumen_rapi() from public, anon, authenticated;
create or replace trigger sales_reps_dokumen_rapi
  before insert or update of nama_dokumen, hp_dokumen, email_dokumen on public.sales_reps
  for each row execute function public.sales_reps_dokumen_rapi();

do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.sales_reps'::regclass
                    and conname = 'sales_reps_dokumen_sah') then
    alter table public.sales_reps add constraint sales_reps_dokumen_sah check (
      (nama_dokumen is null or char_length(nama_dokumen) between 1 and 120)
      and (hp_dokumen is null or hp_dokumen ~ '^[1-9][0-9]{8,15}$')
      and (email_dokumen is null or (char_length(email_dokumen) <= 200
                                     and email_dokumen ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')));
  end if;
end $$;

-- contoh penawaran Hannes 9 Okt (040/PQ/RSG/IX/2026)
update public.sales_reps
   set nama_dokumen = 'Riksa Sri Gustiana,S.Sos', hp_dokumen = '+62 878-0017-3413', email_dokumen = 'riksa@rodahammerindo.com'
 where nama = 'Riksa' and jenis = 'orang' and nama_dokumen is null and hp_dokumen is null and email_dokumen is null;

do $$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'public.sales_reps'::regclass and tgname = 'sales_reps_dokumen_rapi') then
    raise exception '139p: trigger sales_reps_dokumen_rapi belum terpasang';
  end if;
end $$;
