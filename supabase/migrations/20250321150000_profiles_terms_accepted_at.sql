-- 약관 동의 시각 (로그인 후 [TermsAcceptanceScreen]에서 upsert)
alter table public.profiles
  add column if not exists terms_accepted_at timestamptz;
