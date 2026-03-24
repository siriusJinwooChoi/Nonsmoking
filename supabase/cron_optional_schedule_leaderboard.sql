-- pg_cron 확장 활성화(Database → Extensions) 후 실행
-- 매일 15:00 UTC = 한국 00:00 에 일일 랭킹 스냅샷 갱신

create extension if not exists pg_cron with schema extensions;

do $$
declare
  jid int;
begin
  select j.jobid into jid
  from cron.job j
  where j.jobname = 'game_leaderboard_daily_kst_midnight'
  limit 1;
  if jid is not null then
    perform cron.unschedule(jid);
  end if;
exception
  when undefined_table then
    null;
end $$;

select cron.schedule(
  'game_leaderboard_daily_kst_midnight',
  '0 15 * * *',
  $$select public.refresh_game_leaderboard_daily();$$
);
