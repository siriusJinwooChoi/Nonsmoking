-- 알림에 사용하는 선택 이유 문구(앱 prefs: selectedReasonText)
-- Supabase SQL Editor에서 실행하거나 supabase db push로 적용

alter table public.reasons
  add column if not exists selected_reason_text text;
