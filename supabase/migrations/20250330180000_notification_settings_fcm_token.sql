-- FCM 기기 토큰 (서버에서 금연 리마인더 푸시용)
alter table public.notification_settings
  add column if not exists fcm_token text;

comment on column public.notification_settings.fcm_token is
  'Firebase Cloud Messaging 기기 토큰 (선택, 서버 스케줄 푸시)';
