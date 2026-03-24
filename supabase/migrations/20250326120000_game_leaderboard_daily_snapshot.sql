-- =============================================================================
-- 일일 게임 랭킹 스냅샷: 자정(KST) 기준으로 game_stats를 집계해 당일 표시용으로 고정
-- (같은 날 안에는 기록을 갱신해도 랭킹 순위는 전날 자정에 확정된 스냅샷 기준)
-- =============================================================================

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

comment on table public.game_leaderboard_daily is
  '게임 랭킹 일일 스냅샷(한국 자정 기준 갱신). metric_value: 초/레벨/점수(종류는 game_kind로 구분)';

alter table public.game_leaderboard_daily enable row level security;

drop policy if exists game_leaderboard_daily_select_auth on public.game_leaderboard_daily;
create policy game_leaderboard_daily_select_auth on public.game_leaderboard_daily
  for select to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- 스냅샷 갱신 (SECURITY DEFINER — cron / SQL Editor에서 호출)
-- ---------------------------------------------------------------------------
create or replace function public.refresh_game_leaderboard_daily(p_date date default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := coalesce(p_date, (timezone('Asia/Seoul', now()))::date);
begin
  -- 이미 해당 날짜 스냅샷이 있으면 유지 (당일 중 game_stats 변경으로 덮어쓰지 않음)
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

comment on function public.refresh_game_leaderboard_daily(date) is
  '한국 날짜 기준 일일 랭킹 스냅샷 재계산. p_date null이면 오늘(Asia/Seoul)';

revoke all on function public.refresh_game_leaderboard_daily(date) from public;
grant execute on function public.refresh_game_leaderboard_daily(date) to service_role;
