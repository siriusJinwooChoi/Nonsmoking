-- 가입(auth.users insert) 시 public 스키마 관련 테이블에 기본 행 자동 생성
-- 적용: Supabase SQL Editor 또는 supabase db push

-- ---------------------------------------------------------------------------
-- 1) 트리거 함수: 신규 사용자마다 모든 테이블에 기본 행
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ms bigint := (floor(extract(epoch from now()) * 1000))::bigint;
begin
  insert into public.profiles (id)
  values (new.id);

  insert into public.user_settings (user_id)
  values (new.id);

  insert into public.quit_progress (user_id, start_time_ms, lung_last_updated_ms)
  values (new.id, now_ms, now_ms);

  insert into public.reasons (user_id)
  values (new.id);

  insert into public.notification_settings (user_id)
  values (new.id);

  insert into public.coins_and_attendance (user_id)
  values (new.id);

  insert into public.tree_progress (user_id, last_water_update_ms)
  values (new.id, now_ms);

  insert into public.cigarette_collection (user_id)
  values (new.id);

  insert into public.game_stats (user_id)
  values (new.id);

  return new;
end;
$$;

-- 트리거는 초기 마이그레이션에서 이미 생성됨 (on_auth_user_created)

-- ---------------------------------------------------------------------------
-- 2) 백필: 이미 가입했으나 일부 테이블만 있던 사용자
-- ---------------------------------------------------------------------------

insert into public.user_settings (user_id)
select u.id
from auth.users u
where not exists (
  select 1 from public.user_settings s where s.user_id = u.id
);

insert into public.quit_progress (user_id, start_time_ms, lung_last_updated_ms)
select
  u.id,
  (floor(extract(epoch from coalesce(u.created_at, now())) * 1000))::bigint,
  (floor(extract(epoch from coalesce(u.created_at, now())) * 1000))::bigint
from auth.users u
where not exists (
  select 1 from public.quit_progress q where q.user_id = u.id
);

insert into public.reasons (user_id)
select u.id
from auth.users u
where not exists (
  select 1 from public.reasons r where r.user_id = u.id
);

insert into public.notification_settings (user_id)
select u.id
from auth.users u
where not exists (
  select 1 from public.notification_settings n where n.user_id = u.id
);

insert into public.coins_and_attendance (user_id)
select u.id
from auth.users u
where not exists (
  select 1 from public.coins_and_attendance c where c.user_id = u.id
);

insert into public.tree_progress (user_id, last_water_update_ms)
select
  u.id,
  (floor(extract(epoch from coalesce(u.created_at, now())) * 1000))::bigint
from auth.users u
where not exists (
  select 1 from public.tree_progress t where t.user_id = u.id
);

insert into public.cigarette_collection (user_id)
select u.id
from auth.users u
where not exists (
  select 1 from public.cigarette_collection cc where cc.user_id = u.id
);

insert into public.game_stats (user_id)
select u.id
from auth.users u
where not exists (
  select 1 from public.game_stats g where g.user_id = u.id
);

-- profiles 는 기존 트리거로 이미 있을 것이므로 별도 백필 없음
-- (없는 경우만 수동으로 맞추면 됨)
