-- PIN-PON online classic: server-scoped queues and authoritative matches to 15.
begin;
create table pong_private.online_queue (
 user_id uuid primary key references auth.users(id) on delete cascade,
 server_id text not null check(server_id in ('arena-1','arena-2','arena-3')),
 room_code text,
 joined_at timestamptz not null default clock_timestamp(),
 seen_at timestamptz not null default clock_timestamp()
);
create index online_queue_server_idx on pong_private.online_queue(server_id,room_code,joined_at);
create table pong_private.online_matches (
 id uuid primary key default gen_random_uuid(),
 server_id text not null check(server_id in ('arena-1','arena-2','arena-3')),
 p1 uuid not null references auth.users(id) on delete cascade,
 p2 uuid not null references auth.users(id) on delete cascade,
 state jsonb not null,
 status text not null default 'playing' check(status in ('playing','finished','abandoned')),
 winner uuid references auth.users(id) on delete cascade,
 reason text,
 seen1 timestamptz not null default clock_timestamp(),
 seen2 timestamptz not null default clock_timestamp(),
 tick_at timestamptz not null default clock_timestamp(),
 dir1 integer not null default 0 check(dir1 between -1 and 1),
 dir2 integer not null default 0 check(dir2 between -1 and 1),
 target1 double precision, target2 double precision,
 rematch1 boolean not null default false, rematch2 boolean not null default false,
 left1 boolean not null default false,left2 boolean not null default false,
 next_match uuid references pong_private.online_matches(id),
 created_at timestamptz not null default clock_timestamp(), finished_at timestamptz,
 check(p1<>p2)
);
create index online_match_p1_idx on pong_private.online_matches(p1,status,created_at desc);
create index online_match_p2_idx on pong_private.online_matches(p2,status,created_at desc);
create index online_match_winner_idx on pong_private.online_matches(winner);
create index online_match_next_idx on pong_private.online_matches(next_match);
create index online_match_board_idx on pong_private.online_matches(server_id,winner) where status='finished';
alter table pong_private.online_queue enable row level security;
alter table pong_private.online_matches enable row level security;
revoke all on pong_private.online_queue,pong_private.online_matches from public,anon,authenticated;
create policy online_queue_private on pong_private.online_queue for all to anon,authenticated using(false) with check(false);
create policy online_matches_private on pong_private.online_matches for all to anon,authenticated using(false) with check(false);

create function pong_private.online_uid() returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null or not exists(select 1 from auth.users where id=u and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then raise exception 'Verified sign-in required'; end if;
 return u;
end $$;
create function pong_private.online_initial_state() returns jsonb language sql volatile security invoker set search_path='' as $$
 select jsonb_build_object('x',450,'y',250,'vx',case when random()<.5 then -420 else 420 end,'vy',(random()-.5)*180,'ly',195,'ry',195,'ls',0,'rs',0,'pause',2,'seq',0);
$$;
-- Pure physics function. The caller supplies only a bounded paddle input, never ball/score state.
create function pong_private.online_step(s jsonb,dt double precision,d1 integer,d2 integer,t1 double precision,t2 double precision) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 x double precision:=(s->>'x')::double precision;y double precision:=(s->>'y')::double precision;
 vx double precision:=(s->>'vx')::double precision;vy double precision:=(s->>'vy')::double precision;
 ly double precision:=(s->>'ly')::double precision;ry double precision:=(s->>'ry')::double precision;
 ls integer:=(s->>'ls')::integer;rs integer:=(s->>'rs')::integer;
 pause double precision:=(s->>'pause')::double precision;
 steps integer:=greatest(1,ceil(dt*120)::integer);h double precision:=dt/steps;
 oldx double precision;angle double precision;speed double precision;i integer;
begin
 if ls>=15 or rs>=15 then return s; end if;
 for i in 1..steps loop
  if t1 is null then ly:=ly+d1*430*h; else ly:=ly+greatest(-430*h,least(430*h,t1*390-ly)); end if;
  if t2 is null then ry:=ry+d2*430*h; else ry:=ry+greatest(-430*h,least(430*h,t2*390-ry)); end if;
  ly:=greatest(0,least(390,ly));ry:=greatest(0,least(390,ry));
  if pause>0 then pause:=greatest(0,pause-h);continue; end if;
  oldx:=x;x:=x+vx*h;y:=y+vy*h;
  if y<8 then y:=16-y;vy:=abs(vy); elsif y>492 then y:=984-y;vy:=-abs(vy); end if;
  if vx<0 and oldx>=52 and x<=52 and y>=ly-8 and y<=ly+118 then
   angle:=greatest(-1,least(1,(y-ly-55)/55))*pi()/3;speed:=least(820,sqrt(vx*vx+vy*vy)+15);vx:=speed*cos(angle);vy:=speed*sin(angle);x:=52;
  elsif vx>0 and oldx<=862 and x>=862 and y>=ry-8 and y<=ry+118 then
   angle:=greatest(-1,least(1,(y-ry-55)/55))*pi()/3;speed:=least(820,sqrt(vx*vx+vy*vy)+15);vx:=-speed*cos(angle);vy:=speed*sin(angle);x:=862;
  end if;
  if x<0 or x>900 then
   if x<0 then rs:=rs+1;vx:=420; else ls:=ls+1;vx:=-420; end if;
   x:=450;y:=250;vy:=0;pause:=.85;
   if ls>=15 or rs>=15 then vx:=0;vy:=0;exit; end if;
  end if;
 end loop;
 return jsonb_build_object('x',x,'y',y,'vx',vx,'vy',vy,'ly',ly,'ry',ry,'ls',ls,'rs',rs,'pause',pause,'seq',coalesce((s->>'seq')::integer,0)+1);
end $$;
create function pong_private.online_snapshot(mid uuid,u uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m pong_private.online_matches;n1 text;n2 text;
begin
 if u is distinct from auth.uid() then raise exception 'Forbidden'; end if;
 select * into m from pong_private.online_matches where id=mid;
 if not found or (u<>m.p1 and u<>m.p2) then raise exception 'Forbidden'; end if;
 select coalesce(nullif(left(trim(raw_user_meta_data->>'pong_name'),24),''),'Player 1') into n1 from auth.users where id=m.p1;
 select coalesce(nullif(left(trim(raw_user_meta_data->>'pong_name'),24),''),'Player 2') into n2 from auth.users where id=m.p2;
 return jsonb_build_object('kind','match','id',m.id,'server',m.server_id,'side',case when u=m.p1 then 'left' else 'right' end,
 'state',m.state,'status',m.status,'names',jsonb_build_array(n1,n2),'winner',case when m.winner=m.p1 then 'left' when m.winner=m.p2 then 'right' else null end,
 'reason',m.reason,'mineRequested',case when u=m.p1 then m.rematch1 else m.rematch2 end,'peerRequested',case when u=m.p1 then m.rematch2 else m.rematch1 end,
 'canRematch',m.status='finished' and not m.left1 and not m.left2 and m.finished_at>clock_timestamp()-interval '2 minutes');
end $$;
create function pong_private.online_join(p_server text,p_kind text,p_room text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=pong_private.online_uid();peer uuid;code text;mid uuid;oldq pong_private.online_queue;
begin
 if p_server not in ('arena-1','arena-2','arena-3') or p_kind not in ('auto','create','room') then raise exception 'Invalid server or queue'; end if;
 perform pg_advisory_xact_lock(hashtext('pong-online-queue'));
 delete from pong_private.online_queue where seen_at<clock_timestamp()-interval '20 seconds';
 update pong_private.online_matches set status='abandoned',finished_at=clock_timestamp(),reason='timeout' where status='playing' and greatest(seen1,seen2)<clock_timestamp()-interval '30 seconds';
 select id into mid from pong_private.online_matches where status='playing' and (p1=u or p2=u) order by created_at desc limit 1;
 if mid is not null then return pong_private.online_snapshot(mid,u); end if;
 select * into oldq from pong_private.online_queue where user_id=u;
 if found and oldq.server_id=p_server and ((p_kind='auto' and oldq.room_code is null) or (p_kind<>'auto' and oldq.room_code is not null and (p_kind='create' or oldq.room_code=upper(trim(p_room))))) then
  update pong_private.online_queue set seen_at=clock_timestamp() where user_id=u;
  return jsonb_build_object('kind','waiting','server',p_server,'room',oldq.room_code);
 end if;
 delete from pong_private.online_queue where user_id=u;
 if p_kind='create' then
  loop
   code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
   exit when not exists(select 1 from pong_private.online_queue where server_id=p_server and room_code=code);
  end loop;
 elsif p_kind='room' then
  code:=upper(trim(p_room));
  if code !~ '^[A-F0-9]{6}$' then raise exception 'Room not found'; end if;
 end if;
 if p_kind<>'create' then
  select user_id into peer from pong_private.online_queue where server_id=p_server and room_code is not distinct from code and user_id<>u order by joined_at limit 1 for update;
 end if;
 if peer is not null then
  insert into pong_private.online_matches(server_id,p1,p2,state) values(p_server,peer,u,pong_private.online_initial_state()) returning id into mid;
  delete from pong_private.online_queue where user_id in (u,peer);
  return pong_private.online_snapshot(mid,u);
 end if;
 if p_kind='room' then raise exception 'Room not found'; end if;
 insert into pong_private.online_queue(user_id,server_id,room_code) values(u,p_server,code);
 return jsonb_build_object('kind','waiting','server',p_server,'room',code);
end $$;
create function pong_private.online_poll(p_match uuid,p_dir integer,p_target double precision) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=pong_private.online_uid();m pong_private.online_matches;mid uuid:=p_match;q pong_private.online_queue;elapsed double precision;nowt timestamptz;newstate jsonb;
begin
 if p_dir not between -1 and 1 or (p_target is not null and (p_target<0 or p_target>1 or p_target::text in ('NaN','Infinity','-Infinity'))) then raise exception 'Invalid input'; end if;
 if mid is null then
  select id into mid from pong_private.online_matches where status='playing' and (p1=u or p2=u) order by created_at desc limit 1;
  if mid is null then
   update pong_private.online_queue set seen_at=clock_timestamp() where user_id=u and seen_at>clock_timestamp()-interval '20 seconds' returning * into q;
   if found then return jsonb_build_object('kind','waiting','server',q.server_id,'room',q.room_code); end if;
   return jsonb_build_object('kind','idle');
  end if;
 end if;
 select * into m from pong_private.online_matches where id=mid for update;
 if not found or (m.p1<>u and m.p2<>u) then raise exception 'Forbidden'; end if;
 if m.next_match is not null then
  mid:=m.next_match;select * into m from pong_private.online_matches where id=mid for update;
  if not found or (m.p1<>u and m.p2<>u) then raise exception 'Forbidden'; end if;
 end if;
 if m.status<>'playing' then return pong_private.online_snapshot(mid,u); end if;
 nowt:=clock_timestamp();
 if (u=m.p1 and m.seen2<nowt-interval '15 seconds') or (u=m.p2 and m.seen1<nowt-interval '15 seconds') then
  update pong_private.online_matches set status='finished',winner=u,reason='timeout',finished_at=nowt where id=mid;
  return pong_private.online_snapshot(mid,u);
 end if;
 if u=m.p1 then m.seen1:=nowt;m.dir1:=p_dir;m.target1:=p_target;else m.seen2:=nowt;m.dir2:=p_dir;m.target2:=p_target;end if;
 elapsed:=greatest(0,least(.25,extract(epoch from nowt-m.tick_at)));
 newstate:=pong_private.online_step(m.state,elapsed,case when m.seen1<nowt-interval '1 second' then 0 else m.dir1 end,case when m.seen2<nowt-interval '1 second' then 0 else m.dir2 end,m.target1,m.target2);
 update pong_private.online_matches set state=newstate,tick_at=nowt,seen1=m.seen1,seen2=m.seen2,dir1=m.dir1,dir2=m.dir2,target1=m.target1,target2=m.target2,
 status=case when (newstate->>'ls')::integer>=15 or (newstate->>'rs')::integer>=15 then 'finished' else 'playing' end,
 winner=case when (newstate->>'ls')::integer>=15 then m.p1 when (newstate->>'rs')::integer>=15 then m.p2 else null end,
 reason=case when (newstate->>'ls')::integer>=15 or (newstate->>'rs')::integer>=15 then 'score' else null end,
 finished_at=case when (newstate->>'ls')::integer>=15 or (newstate->>'rs')::integer>=15 then nowt else null end where id=mid;
 return pong_private.online_snapshot(mid,u);
end $$;
create function pong_private.online_rematch(p_match uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=pong_private.online_uid();m pong_private.online_matches;mid uuid;
begin
 perform pg_advisory_xact_lock(hashtext('pong-online-queue'));
 select * into m from pong_private.online_matches where id=p_match for update;
 if not found or (u<>m.p1 and u<>m.p2) then raise exception 'Forbidden';end if;
 if m.next_match is not null then return pong_private.online_snapshot(m.next_match,u);end if;
 if m.status<>'finished' or m.left1 or m.left2 or m.finished_at<clock_timestamp()-interval '2 minutes' then raise exception 'Rematch unavailable';end if;
 if u=m.p1 then m.rematch1:=true;else m.rematch2:=true;end if;
 update pong_private.online_matches set rematch1=m.rematch1,rematch2=m.rematch2 where id=m.id;
 if m.rematch1 and m.rematch2 then
  if exists(select 1 from pong_private.online_matches where status='playing' and (p1 in (m.p1,m.p2) or p2 in (m.p1,m.p2))) or exists(select 1 from pong_private.online_queue where user_id in (m.p1,m.p2)) then raise exception 'Rematch unavailable';end if;
  insert into pong_private.online_matches(server_id,p1,p2,state) values(m.server_id,m.p2,m.p1,pong_private.online_initial_state()) returning id into mid;
  update pong_private.online_matches set next_match=mid where id=m.id;
  return pong_private.online_snapshot(mid,u);
 end if;
 return pong_private.online_snapshot(m.id,u);
end $$;
create function pong_private.online_leave(p_match uuid) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=pong_private.online_uid();m pong_private.online_matches;mid uuid:=p_match;
begin
 perform pg_advisory_xact_lock(hashtext('pong-online-queue'));
 delete from pong_private.online_queue where user_id=u;
 if mid is null then select id into mid from pong_private.online_matches where status='playing' and (p1=u or p2=u) order by created_at desc limit 1;end if;
 if mid is null then return;end if;
 select * into m from pong_private.online_matches where id=mid for update;
 if not found or (u<>m.p1 and u<>m.p2) then raise exception 'Forbidden';end if;
 if m.next_match is not null then mid:=m.next_match;select * into m from pong_private.online_matches where id=mid for update;end if;
 update pong_private.online_matches set left1=left1 or u=p1,left2=left2 or u=p2,
 status=case when status='playing' then 'finished' else status end,
 winner=case when status='playing' then case when u=p1 then p2 else p1 end else winner end,
 reason=case when status='playing' then 'left' else reason end,
 finished_at=case when status='playing' then clock_timestamp() else finished_at end where id=mid;
end $$;
-- Public standings contain no account IDs or emails; results originate only from server physics.
create function pong_private.online_board(p_server text) returns table(display_name text,wins bigint,points bigint) language sql stable security definer set search_path='' as $$
 select coalesce(nullif(left(trim(u.raw_user_meta_data->>'pong_name'),24),''),'Player'),count(*),sum(case when m.reason='score' then 15-least((m.state->>'ls')::integer,(m.state->>'rs')::integer) else 0 end)::bigint
 from pong_private.online_matches m join auth.users u on u.id=m.winner where m.status='finished' and m.winner is not null and m.server_id=p_server
 group by m.winner,u.raw_user_meta_data order by count(*) desc,sum(case when m.reason='score' then 15-least((m.state->>'ls')::integer,(m.state->>'rs')::integer) else 0 end) desc,min(m.finished_at) asc,m.winner limit 50;
$$;
-- Revoke Postgres' default PUBLIC execution on every new private implementation.
revoke all on function pong_private.online_uid(),pong_private.online_initial_state(),pong_private.online_step(jsonb,double precision,integer,integer,double precision,double precision),pong_private.online_snapshot(uuid,uuid),pong_private.online_join(text,text,text),pong_private.online_poll(uuid,integer,double precision),pong_private.online_rematch(uuid),pong_private.online_leave(uuid),pong_private.online_board(text) from public,anon,authenticated;
grant execute on function pong_private.online_join(text,text,text),pong_private.online_poll(uuid,integer,double precision),pong_private.online_rematch(uuid),pong_private.online_leave(uuid) to authenticated;
grant execute on function pong_private.online_board(text) to anon,authenticated;
create function public.pong_online_join(p_server text,p_kind text default 'auto',p_room text default '') returns jsonb language sql security invoker set search_path='' as $$select pong_private.online_join(p_server,p_kind,p_room);$$;
create function public.pong_online_poll(p_match uuid default null,p_dir integer default 0,p_target double precision default null) returns jsonb language sql security invoker set search_path='' as $$select pong_private.online_poll(p_match,p_dir,p_target);$$;
create function public.pong_online_rematch(p_match uuid) returns jsonb language sql security invoker set search_path='' as $$select pong_private.online_rematch(p_match);$$;
create function public.pong_online_leave(p_match uuid default null) returns void language sql security invoker set search_path='' as $$select pong_private.online_leave(p_match);$$;
create function public.pong_online_board(p_server text) returns table(display_name text,wins bigint,points bigint) language sql stable security invoker set search_path='' as $$select * from pong_private.online_board(p_server);$$;
revoke all on function public.pong_online_join(text,text,text),public.pong_online_poll(uuid,integer,double precision),public.pong_online_rematch(uuid),public.pong_online_leave(uuid),public.pong_online_board(text) from public,anon,authenticated;
grant execute on function public.pong_online_join(text,text,text),public.pong_online_poll(uuid,integer,double precision),public.pong_online_rematch(uuid),public.pong_online_leave(uuid) to authenticated;
grant execute on function public.pong_online_board(text) to anon,authenticated;
notify pgrst,'reload schema';
commit;
