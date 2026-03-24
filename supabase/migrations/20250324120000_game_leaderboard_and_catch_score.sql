-- 랭킹 조회용 SELECT 정책 + 담배맞추기 최고 점수 컬럼

alter table public.game_stats
  add column if not exists cigarette_catch_best_score int not null default 0;

alter table public.game_stats
  drop constraint if exists game_stats_cigarette_catch_best_score_non_negative;

alter table public.game_stats
  add constraint game_stats_cigarette_catch_best_score_non_negative
  check (cigarette_catch_best_score >= 0);

comment on column public.game_stats.cigarette_catch_best_score is '담배맞추기 최고 점수';

-- 로그인 사용자: 다른 사용자의 미니게임 기록·닉네임을 랭킹 조회용으로 읽을 수 있음
-- (재실행 시 중복 오류 방지)
drop policy if exists game_stats_select_leaderboard on public.game_stats;
create policy game_stats_select_leaderboard on public.game_stats
  for select to authenticated
  using (true);

drop policy if exists profiles_select_leaderboard on public.profiles;
create policy profiles_select_leaderboard on public.profiles
  for select to authenticated
  using (true);
