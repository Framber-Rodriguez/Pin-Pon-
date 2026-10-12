-- PIN-PON — Framber Rodriguez. Run once in the project's SQL editor.
begin;
create schema if not exists pong_private;
revoke all on schema pong_private from public;
grant usage on schema pong_private to anon, authenticated;
create table if not exists pong_private.pong_results (
 match_id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 difficulty text not null check (difficulty in ('easy','normal','hard','veryHard','impossible')),
 ruleset text not null check (ruleset in ('classic','items')),
 player_score smallint not null check (player_score between 0 and 10),
 opponent_score smallint not null check (opponent_score between 0 and 10),
 created_at timestamptz not null default now(),
 check ((player_score = 10 and opponent_score < 10) or (opponent_score = 10 and player_score < 10))
);
create index if not exists pong_category_idx on pong_private.pong_results(difficulty,ruleset,user_id);
create index if not exists pong_user_time_idx on pong_private.pong_results(user_id,created_at desc);
alter table pong_private.pong_results enable row level security;
revoke all on pong_private.pong_results from anon,authenticated;
create policy pong_no_direct_access on pong_private.pong_results for all to anon, authenticated using (false) with check (false);
-- No browser can insert, edit or read private per-user rows directly.
create or replace function pong_private.pong_submit_result(p_match_id uuid,p_difficulty text,p_ruleset text,p_player_score integer,p_opponent_score integer)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
 if uid is null or not exists (select 1 from auth.users u where u.id=uid and u.email_confirmed_at is not null and coalesce(u.is_anonymous,false)=false) then
  raise exception 'Verified sign-in required';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if exists(select 1 from pong_private.pong_results where match_id=p_match_id and user_id=uid) then return; end if;
 if exists(select 1 from pong_private.pong_results where user_id=uid and created_at>now()-interval '20 seconds') then raise exception 'Please wait before submitting another result'; end if;
 insert into pong_private.pong_results(match_id,user_id,difficulty,ruleset,player_score,opponent_score)
 values(p_match_id,uid,p_difficulty,p_ruleset,p_player_score,p_opponent_score);
end $$;
revoke all on function pong_private.pong_submit_result(uuid,text,text,integer,integer) from public,anon;
grant execute on function pong_private.pong_submit_result(uuid,text,text,integer,integer) to authenticated;
create or replace function pong_private.pong_leaderboard(p_difficulty text,p_ruleset text)
returns table(display_name text,wins bigint,points bigint)
language sql stable security definer set search_path = '' as $$
 select coalesce(nullif(left(trim(u.raw_user_meta_data->>'pong_name'),24),''),'Player-'||left(r.user_id::text,6)),
 count(*) filter(where r.player_score=10),
 coalesce(sum(r.player_score-r.opponent_score) filter(where r.player_score=10),0)
 from pong_private.pong_results r join auth.users u on u.id=r.user_id
 where r.difficulty=p_difficulty and r.ruleset=p_ruleset
 group by r.user_id,u.raw_user_meta_data
 having count(*) filter(where r.player_score=10)>0
 order by count(*) filter(where r.player_score=10) desc,
 coalesce(sum(r.player_score-r.opponent_score) filter(where r.player_score=10),0) desc,
 min(r.created_at) asc, r.user_id asc limit 50;
$$;
revoke all on function pong_private.pong_leaderboard(text,text) from public;
grant execute on function pong_private.pong_leaderboard(text,text) to anon,authenticated;
-- Public RPC entry points use invoker privileges. Privileged implementations
-- and raw match rows live in a schema that is not exposed through PostgREST.
create or replace function public.pong_submit_result(p_match_id uuid,p_difficulty text,p_ruleset text,p_player_score integer,p_opponent_score integer)
returns void language sql security invoker set search_path = '' as $$
 select pong_private.pong_submit_result(p_match_id,p_difficulty,p_ruleset,p_player_score,p_opponent_score);
$$;
revoke all on function public.pong_submit_result(uuid,text,text,integer,integer) from public,anon;
grant execute on function public.pong_submit_result(uuid,text,text,integer,integer) to authenticated;
create or replace function public.pong_leaderboard(p_difficulty text,p_ruleset text)
returns table(display_name text,wins bigint,points bigint)
language sql stable security invoker set search_path = '' as $$
 select * from pong_private.pong_leaderboard(p_difficulty,p_ruleset);
$$;
revoke all on function public.pong_leaderboard(text,text) from public;
grant execute on function public.pong_leaderboard(text,text) to anon,authenticated;
-- The dashboard automatic-RLS trigger remains usable by its owner only.
do $$ begin if to_regprocedure('public.rls_auto_enable()') is not null then execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated'; end if; end $$;
notify pgrst, 'reload schema';
commit;
