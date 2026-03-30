-- FCM 미접속·금연 이유 중복 방지 (서버 크론 전용, 클라이언트는 sync 시 보존만)
alter table public.notification_settings
  add column if not exists fcm_last_inactivity_sent_ms bigint;

alter table public.notification_settings
  add column if not exists fcm_last_reason_sent_ymd text;

comment on column public.notification_settings.fcm_last_inactivity_sent_ms is
  '서버 FCM 비접속 알림 마지막 전송 시각(ms, Unix epoch)';
comment on column public.notification_settings.fcm_last_reason_sent_ymd is
  '서버 FCM 금연 이유(12:01) 알림 마지막 전송일 (Asia/Seoul yyyy-mm-dd)';
