-- 금연뱅크 초기 스키마
-- 적용: Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣기 → Run
-- (로컬 CLI 사용 시: supabase db push 등)

-- ---------------------------------------------------------------------------
-- 1) 테이블
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  display_name text,
  terms_accepted_at timestamptz
);

create table public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  is_configured boolean not null default false,
  daily_cigarettes int not null default 0,
  cigarettes_per_pack int not null default 20,
  price_per_pack int not null default 4500,
  duration_days int
);

create table public.quit_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  start_time_ms bigint not null,
  failure_count int not null default 0,
  goal_days int,
  goal_congratulated_day int,
  lung_health int not null default 100,
  lung_last_updated_ms bigint not null,
  pinned_reason_text text,
  constraint quit_progress_lung_health_check check (lung_health >= 0 and lung_health <= 100),
  constraint quit_progress_failure_count_check check (failure_count >= 0)
);

create table public.reasons (
  user_id uuid primary key references auth.users (id) on delete cascade,
  reasons_json jsonb not null default '[]'::jsonb,
  selected_reason_id text,
  selected_reason_text text
);

create table public.notification_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  reminder_times_json jsonb not null default '[]'::jsonb,
  reason_notification_enabled boolean not null default false,
  inactivity_notification_enabled boolean not null default true,
  attendance_reminder_enabled boolean not null default true,
  last_app_open_time_ms bigint
);

create table public.coins_and_attendance (
  user_id uuid primary key references auth.users (id) on delete cascade,
  golden_coins int not null default 0,
  attendance_streak_day int not null default 1,
  attendance_last_date date,
  constraint coins_golden_non_negative check (golden_coins >= 0),
  constraint attendance_streak_positive check (attendance_streak_day >= 1)
);

create table public.tree_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  growth_stage int not null default 1,
  water int not null default 0,
  current_water int not null default 0,
  last_water_update_ms bigint not null default (floor(extract(epoch from now()) * 1000))::bigint,
  saved_trees_count int not null default 0,
  constraint tree_growth_non_negative check (growth_stage >= 0),
  constraint tree_water_non_negative check (water >= 0 and current_water >= 0 and saved_trees_count >= 0)
);

create table public.cigarette_collection (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_collection_window text,
  session_window text,
  session_asset text,
  session_attempts int not null default 0,
  collected_asset_paths jsonb not null default '[]'::jsonb,
  constraint session_attempts_range check (session_attempts >= 0 and session_attempts <= 5)
);

-- 미니게임 기록: 앱의 SharedPreferences 키와 대응
-- - number_sequence_best_seconds: 1~30 순서 게임 최고 기록(초), 미도전 시 null
-- - word_game_level: 단어 찾기 레벨
-- - timing_tap_best_score: 완벽 타이밍 최고 점수
-- - cigarette_catch_best_stage: 담배맞추기 최고 도달 단계
create table public.game_stats (
  user_id uuid primary key references auth.users (id) on delete cascade,
  number_sequence_best_seconds double precision,
  word_game_level int not null default 1,
  timing_tap_best_score int not null default 0,
  cigarette_catch_best_stage int not null default 0,
  constraint word_game_level_range check (word_game_level >= 1 and word_game_level <= 100),
  constraint timing_tap_best_non_negative check (timing_tap_best_score >= 0),
  constraint cigarette_catch_best_non_negative check (cigarette_catch_best_stage >= 0)
);

-- ---------------------------------------------------------------------------
-- 2) 신규 가입 시 프로필 자동 생성
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 3) Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.quit_progress enable row level security;
alter table public.reasons enable row level security;
alter table public.notification_settings enable row level security;
alter table public.coins_and_attendance enable row level security;
alter table public.tree_progress enable row level security;
alter table public.cigarette_collection enable row level security;
alter table public.game_stats enable row level security;

-- profiles: 본인 행만
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = id);
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
create policy profiles_insert_own on public.profiles
  for insert with check (auth.uid() = id);

-- user_id 기준 테이블 공통 패턴
create policy user_settings_all_own on public.user_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy quit_progress_all_own on public.quit_progress
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy reasons_all_own on public.reasons
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy notification_settings_all_own on public.notification_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy coins_and_attendance_all_own on public.coins_and_attendance
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy tree_progress_all_own on public.tree_progress
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy cigarette_collection_all_own on public.cigarette_collection
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy game_stats_all_own on public.game_stats
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
