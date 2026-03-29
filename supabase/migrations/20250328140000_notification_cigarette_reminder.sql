-- 담배 수집 정각 알림 on/off 를 서버·다기기 동기화에 포함
alter table public.notification_settings
  add column if not exists cigarette_collection_reminder_enabled boolean not null default true;

comment on column public.notification_settings.cigarette_collection_reminder_enabled is
  '09/12/18/22 정각 담배 수집 가능 알림 (앱 로컬 키와 동기화)';
