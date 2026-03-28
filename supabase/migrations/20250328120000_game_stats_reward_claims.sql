-- 게임 일일 보상 중복 방지 + 동기화 시각(보상 검증용)
-- Supabase SQL Editor에서 기존 DB에도 동일하게 적용해 주세요.

create table if not exists public.game_reward_claims (
  user_id uuid not null references auth.users (id) on delete cascade,
  claim_key text not null,
  coins_granted int not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, claim_key)
);

create index if not exists game_reward_claims_user_created_idx
  on public.game_reward_claims (user_id, created_at desc);

comment on table public.game_reward_claims is
  '게임 일일 보상 등 서버 검증 보상의 중복 지급 방지(클라이언트 직접 접근 없음, API 서버만 사용)';

alter table public.game_reward_claims enable row level security;

revoke all on public.game_reward_claims from anon;
revoke all on public.game_reward_claims from authenticated;
grant all on public.game_reward_claims to service_role;

alter table public.game_stats
  add column if not exists stats_updated_at timestamptz default now();

comment on column public.game_stats.stats_updated_at is
  '게임 기록이 서버에 마지막으로 반영된 시각. 일일 보상 검증에 사용';
