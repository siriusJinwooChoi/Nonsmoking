-- =============================================================================
-- Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣기 → Run
--
-- 앱 현재 버전에 맞춘 DB 보강 (이미 초기 스키마가 적용된 프로젝트용).
-- 여러 번 실행해도 안전하도록 IF NOT EXISTS / DROP IF EXISTS 사용.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- profiles / reasons (초기 스키마 이후 추가된 컬럼이 없을 때만 반영)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists terms_accepted_at timestamptz;

alter table public.reasons
  add column if not exists selected_reason_text text;

-- ---------------------------------------------------------------------------
-- game_stats: 담배맞추기 최고 점수 + 랭킹용 RLS
-- ---------------------------------------------------------------------------
alter table public.game_stats
  add column if not exists cigarette_catch_best_score int not null default 0;

alter table public.game_stats
  drop constraint if exists game_stats_cigarette_catch_best_score_non_negative;

alter table public.game_stats
  add constraint game_stats_cigarette_catch_best_score_non_negative
  check (cigarette_catch_best_score >= 0);

comment on column public.game_stats.cigarette_catch_best_score is '담배맞추기 최고 점수';

drop policy if exists game_stats_select_leaderboard on public.game_stats;
create policy game_stats_select_leaderboard on public.game_stats
  for select to authenticated
  using (true);

drop policy if exists profiles_select_leaderboard on public.profiles;
create policy profiles_select_leaderboard on public.profiles
  for select to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- 일일 게임 랭킹 스냅샷 (자정 KST 기준 확정, 당일 중에는 덮어쓰지 않음)
-- 아래는 migrations/20250326120000_game_leaderboard_daily_snapshot.sql 과 동일
-- ---------------------------------------------------------------------------
create table if not exists public.game_leaderboard_daily (
  id bigserial primary key,
  snapshot_date date not null,
  game_kind text not null
    check (game_kind in (
      'number_sequence',
      'word_game',
      'cigarette_catch',
      'timing_tap'
    )),
  user_id uuid not null references auth.users (id) on delete cascade,
  rank int not null,
  metric_value double precision not null,
  display_name text,
  created_at timestamptz not null default now(),
  unique (snapshot_date, game_kind, user_id)
);

create index if not exists game_leaderboard_daily_snapshot_kind_rank_idx
  on public.game_leaderboard_daily (snapshot_date, game_kind, rank);

alter table public.game_leaderboard_daily enable row level security;

drop policy if exists game_leaderboard_daily_select_auth on public.game_leaderboard_daily;
create policy game_leaderboard_daily_select_auth on public.game_leaderboard_daily
  for select to authenticated
  using (true);

create or replace function public.refresh_game_leaderboard_daily(p_date date default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := coalesce(p_date, (timezone('Asia/Seoul', now()))::date);
begin
  if exists (
    select 1 from public.game_leaderboard_daily d where d.snapshot_date = v_date limit 1
  ) then
    return;
  end if;

  insert into public.game_leaderboard_daily (
    snapshot_date, game_kind, user_id, rank, metric_value, display_name
  )
  select
    v_date,
    'number_sequence',
    gs.user_id,
    row_number() over (
      order by gs.number_sequence_best_seconds asc nulls last, gs.user_id
    ),
    gs.number_sequence_best_seconds::double precision,
    nullif(trim(p.display_name::text), '')
  from public.game_stats gs
  left join public.profiles p on p.id = gs.user_id
  where gs.number_sequence_best_seconds is not null;

  insert into public.game_leaderboard_daily (
    snapshot_date, game_kind, user_id, rank, metric_value, display_name
  )
  select
    v_date,
    'word_game',
    gs.user_id,
    row_number() over (order by gs.word_game_level desc, gs.user_id),
    gs.word_game_level::double precision,
    nullif(trim(p.display_name::text), '')
  from public.game_stats gs
  left join public.profiles p on p.id = gs.user_id;

  insert into public.game_leaderboard_daily (
    snapshot_date, game_kind, user_id, rank, metric_value, display_name
  )
  select
    v_date,
    'cigarette_catch',
    gs.user_id,
    row_number() over (order by gs.cigarette_catch_best_score desc, gs.user_id),
    gs.cigarette_catch_best_score::double precision,
    nullif(trim(p.display_name::text), '')
  from public.game_stats gs
  left join public.profiles p on p.id = gs.user_id;

  insert into public.game_leaderboard_daily (
    snapshot_date, game_kind, user_id, rank, metric_value, display_name
  )
  select
    v_date,
    'timing_tap',
    gs.user_id,
    row_number() over (order by gs.timing_tap_best_score desc, gs.user_id),
    gs.timing_tap_best_score::double precision,
    nullif(trim(p.display_name::text), '')
  from public.game_stats gs
  left join public.profiles p on p.id = gs.user_id;
end;
$$;

revoke all on function public.refresh_game_leaderboard_daily(date) from public;
grant execute on function public.refresh_game_leaderboard_daily(date) to service_role;

-- 오늘(한국일) 스냅샷이 없으면 생성 (이미 있으면 함수가 아무 것도 하지 않음)
select public.refresh_game_leaderboard_daily();

-- 자정 자동 갱신은 cron_optional_schedule_leaderboard.sql 참고 (pg_cron 확장 필요)

-- ---------------------------------------------------------------------------
-- game_stats: 일일 게임 보상(클리어·세션 종료 검증용 보조 컬럼)
-- ---------------------------------------------------------------------------
alter table public.game_stats
  add column if not exists number_sequence_last_clear_seconds double precision;

alter table public.game_stats
  add column if not exists timing_tap_last_session_score int;

alter table public.game_stats
  add column if not exists cigarette_catch_last_session_score int;
