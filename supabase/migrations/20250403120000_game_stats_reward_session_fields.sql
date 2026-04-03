-- 일일 게임 보상: 최고 기록이 아닌 클리어/세션 종료에도 검증할 수 있도록 보조 컬럼 추가

alter table public.game_stats
  add column if not exists number_sequence_last_clear_seconds double precision;

alter table public.game_stats
  add column if not exists timing_tap_last_session_score int;

alter table public.game_stats
  add column if not exists cigarette_catch_last_session_score int;

comment on column public.game_stats.number_sequence_last_clear_seconds is '1~30 마지막 클리어 기록(초), 일일 보상 검증용';
comment on column public.game_stats.timing_tap_last_session_score is '완벽 타이밍 직전 종료 시점 점수, 일일 보상 검증용';
comment on column public.game_stats.cigarette_catch_last_session_score is '낙하 맞추기 게임오버 시점 점수, 일일 보상 검증용';
