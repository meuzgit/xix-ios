-- 0021: the cabinet, the rivalry view, rankings and crews (Build Doc 3 step 5; PRD 8.18, 8.19;
-- Pass 6 6d/6e, Pass 7 §3/§4).
--
-- Four things, all reads except the crew RPCs:
--   1. medals become visible to everyone who was in the round, so a rivalry has two sides to it
--   2. crews get a join code and the three RPCs behind create / invite / join / leave
--   3. ranking_entries carry what a board renders, refreshed by a nightly job
--   4. xix.rivalry(other) answers the head-to-head from results and medals

-- ---------------------------------------------------------------------------------------------
-- 1. Medals: yours, and anyone's from a round you were in.
--
-- A rivalry is two people's medals against each other. Under the old policy you could read only your
-- own, so the other half of your own grudge was invisible. A medal from a round you played in is not
-- private from the people you played it with.
-- ---------------------------------------------------------------------------------------------

drop policy if exists medals_select_own on xix.medals;
create policy medals_select_own_or_shared on xix.medals for select to authenticated
  using (profile_id = auth.uid() or xix.is_round_member(round_id));

-- ---------------------------------------------------------------------------------------------
-- 2. Crews: a join code, and create / join / leave.
-- ---------------------------------------------------------------------------------------------

alter table xix.crews add column if not exists join_code text;
update xix.crews set join_code = xix.gen_join_code() where join_code is null;
alter table xix.crews alter column join_code set default xix.gen_join_code();
alter table xix.crews alter column join_code set not null;
create unique index if not exists crews_join_code_key on xix.crews (join_code);

create or replace function xix.create_crew(name text)
returns xix.crews language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; c xix.crews;
begin
  if coalesce(trim(create_crew.name), '') = '' then
    raise exception 'a crew needs a name' using errcode = '22023';
  end if;
  insert into xix.crews (name, owner_id, join_code)
  values (trim(create_crew.name), me, xix.gen_join_code())
  returning * into c;
  insert into xix.crew_members (crew_id, profile_id) values (c.id, me) on conflict do nothing;
  return c;
end;
$$;

-- The invite link's landing: the crew for a code, without joining it. Name and size only — a crew is
-- private, so its board is not readable until you are in it.
create or replace function xix.crew_preview(code text)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare c xix.crews;
begin
  perform xix.require_auth();
  select * into c from xix.crews x where x.join_code = upper(trim(crew_preview.code));
  if not found then
    raise exception 'no crew for that code' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'id', c.id, 'name', c.name, 'join_code', c.join_code,
    'members', (select count(*) from xix.crew_members m where m.crew_id = c.id),
    'mine', exists (select 1 from xix.crew_members m where m.crew_id = c.id and m.profile_id = auth.uid()));
end;
$$;

create or replace function xix.join_crew(code text)
returns xix.crews language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; c xix.crews;
begin
  select * into c from xix.crews x where x.join_code = upper(trim(join_crew.code));
  if not found then
    raise exception 'no crew for that code' using errcode = 'P0002';
  end if;
  insert into xix.crew_members (crew_id, profile_id) values (c.id, me) on conflict do nothing;
  return c;
end;
$$;

create or replace function xix.leave_crew(crew_id uuid)
returns boolean language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id;
begin
  if exists (select 1 from xix.crews c where c.id = leave_crew.crew_id and c.owner_id = me) then
    raise exception 'the owner cannot leave their own crew' using errcode = '55000';
  end if;
  delete from xix.crew_members m where m.crew_id = leave_crew.crew_id and m.profile_id = me;
  return found;
end;
$$;

-- A member may add themselves through join_crew; the owner's own inserts still go through RLS.
drop policy if exists crew_members_insert_owner on xix.crew_members;
create policy crew_members_insert_owner_or_self on xix.crew_members for insert to authenticated
  with check (xix.is_crew_owner(crew_id) or profile_id = auth.uid());
create policy crew_members_delete_self on xix.crew_members for delete to authenticated
  using (profile_id = auth.uid());

-- ---------------------------------------------------------------------------------------------
-- 3. Rankings: what a board draws, refreshed nightly.
--
-- The board shows a name, rounds played and a Level for people who may share no round with the
-- reader, so those travel on the entry rather than being read from profiles, which stay private.
-- Rank and the movement caret are computed by the job; a crew board re-ranks its members at read time.
-- ---------------------------------------------------------------------------------------------

alter table xix.ranking_entries add column if not exists display_name text;
alter table xix.ranking_entries add column if not exists rounds integer not null default 0;
alter table xix.ranking_entries add column if not exists level numeric;
alter table xix.ranking_entries add column if not exists rank integer;
alter table xix.ranking_entries add column if not exists previous_rank integer;

-- Only rounds that count: ended, and confirmed by somebody else or aged past the objection window
-- (PRD 8.11, xix.auto_confirm). A round nobody has confirmed is in nobody's ranking.
create or replace function xix.refresh_rankings()
returns integer language plpgsql security definer set search_path = xix, pg_temp as $$
declare n integer;
begin
  create temp table fresh on commit drop as
  with counted as (
    select p.profile_id, r.id as round_id, r.played_on, res.payload, p.id as player_id
      from xix.rounds r
      join xix.players p on p.round_id = r.id and p.profile_id is not null
      join xix.results res on res.round_id = r.id
     where r.counted_at is not null
       and res.payload ->> 'status' = 'complete'
  ),
  metrics as (
    -- Stableford vs Level, this month and all time: the engine's passive board (PRD 8.11).
    select c.profile_id, 'stableford_vs_level' as metric, w."window",
           sum(coalesce((
             select (e ->> 'value')::numeric
               from jsonb_array_elements(c.payload -> 'leaderboard' -> 'stableford_vs_level') e
              where e ->> 'player' = c.player_id::text), 0)) as value
      from counted c
      cross join (values ('month'), ('all')) as w("window")
     where w."window" = 'all' or c.played_on >= date_trunc('month', current_date)
     group by c.profile_id, w."window"
    union all
    -- Birdies, same two windows.
    select c.profile_id, 'birdies', w."window",
           sum(coalesce((
             select (e ->> 'value')::numeric
               from jsonb_array_elements(c.payload -> 'leaderboard' -> 'birdies') e
              where e ->> 'player' = c.player_id::text), 0))
      from counted c
      cross join (values ('month'), ('all')) as w("window")
     where w."window" = 'all' or c.played_on >= date_trunc('month', current_date)
     group by c.profile_id, w."window"
    union all
    -- Rounds played.
    select c.profile_id, 'rounds', w."window", count(*)::numeric
      from counted c
      cross join (values ('month'), ('all')) as w("window")
     where w."window" = 'all' or c.played_on >= date_trunc('month', current_date)
     group by c.profile_id, w."window"
    union all
    -- Rival Points.
    select c.profile_id, 'rival_points', w."window",
           sum(coalesce((c.payload -> 'rivalPoints' ->> c.player_id::text)::numeric, 0))
      from counted c
      cross join (values ('month'), ('all')) as w("window")
     where w."window" = 'all' or c.played_on >= date_trunc('month', current_date)
     group by c.profile_id, w."window"
  ),
  played as (
    select profile_id, count(*) as rounds from counted group by profile_id
  )
  select m.profile_id, m.metric, m."window", m.value,
         pr.display_name,
         coalesce(pl.rounds, 0)::integer as rounds,
         coalesce(pr.level_index, pr.level_auto) as level,
         -- Tied values share a rank, the way the engine's own leaderboard does (B.4).
         rank() over (partition by m.metric, m."window" order by m.value desc)::integer as rank
    from metrics m
    join xix.profiles pr on pr.id = m.profile_id
    left join played pl on pl.profile_id = m.profile_id;

  -- Yesterday's rank becomes the movement caret.
  insert into xix.ranking_entries (profile_id, metric, "window", value, display_name, rounds, level, rank, previous_rank, computed_at)
  select f.profile_id, f.metric, f."window", f.value, f.display_name, f.rounds, f.level, f.rank,
         (select e.rank from xix.ranking_entries e
           where e.profile_id = f.profile_id and e.metric = f.metric and e."window" = f."window"),
         now()
    from fresh f
  on conflict (profile_id, metric, "window") do update
     set value = excluded.value, display_name = excluded.display_name, rounds = excluded.rounds,
         level = excluded.level, previous_rank = xix.ranking_entries.rank, rank = excluded.rank,
         computed_at = now();

  -- Anybody whose rounds stopped counting drops off the board.
  delete from xix.ranking_entries e
   where not exists (select 1 from fresh f
                      where f.profile_id = e.profile_id and f.metric = e.metric and f."window" = e."window");

  select count(*) into n from fresh;
  return n;
end;
$$;

-- The board itself. Global is everyone; a crew board is its members, re-ranked among themselves.
create or replace function xix.rankings(metric text, "window" text default 'all', crew_id uuid default null)
returns table (profile_id uuid, display_name text, rounds integer, level numeric, value numeric,
               rank integer, previous_rank integer, is_me boolean)
language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare me uuid := xix.require_auth();
begin
  if metric not in ('stableford_vs_level', 'birdies', 'rounds', 'rival_points') then
    raise exception 'no such metric %', metric using errcode = '22023';
  end if;
  if "window" not in ('month', 'all') then
    raise exception 'no such window %', "window" using errcode = '22023';
  end if;
  if crew_id is not null and not xix.is_crew_member(crew_id) then
    raise exception 'not a member of this crew' using errcode = '42501';
  end if;

  return query
  with rows as (
    select e.profile_id, e.display_name, e.rounds, e.level, e.value, e.rank, e.previous_rank
      from xix.ranking_entries e
     where e.metric = rankings.metric and e."window" = rankings."window"
       and (rankings.crew_id is null
            or exists (select 1 from xix.crew_members m where m.crew_id = rankings.crew_id and m.profile_id = e.profile_id))
  )
  select r.profile_id, r.display_name, r.rounds, r.level, r.value,
         case when rankings.crew_id is null then r.rank
              else rank() over (order by r.value desc)::integer end,
         r.previous_rank,
         r.profile_id = me
    from rows r
   order by 6, r.display_name
   limit 200;
end;
$$;

-- Rounds of mine that are waiting on somebody: ended, not counted, no objection yet. The pending row
-- on the board (Pass 6 6e) is built from this.
create or replace function xix.pending_rounds()
returns table (round_id uuid, course text, played_on date, gross integer, ended_at timestamptz,
               confirmed boolean, objected boolean, hours_left numeric)
language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare me uuid := xix.require_auth();
begin
  return query
  select r.id, c.name, r.played_on,
         (select (res.payload -> 'perPlayer' -> p.id::text ->> 'gross')::integer
            from xix.results res where res.round_id = r.id),
         r.ended_at,
         exists (select 1 from xix.confirmations x where x.round_id = r.id and x.profile_id = me and x.action = 'confirm'),
         exists (select 1 from xix.confirmations x where x.round_id = r.id and x.action = 'object'),
         greatest(0, extract(epoch from (r.ended_at + interval '48 hours' - now())) / 3600)::numeric
    from xix.rounds r
    join xix.players p on p.round_id = r.id and p.profile_id = me
    left join xix.courses c on c.id = r.course_id
   where r.status = 'ended' and r.counted_at is null
   order by r.ended_at desc
   limit 20;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 2b. A player's Level is frozen onto their row when they join the round.
--
-- `players.level_snapshot` has existed since 0002 and nothing ever wrote to it, so every round was
-- played by people with no Level: net games had nothing to work from, and the passive Stableford vs
-- Level metric the boards rank on never appeared at all. A Level belongs to the round as it was
-- played, not as it stands today, which is what a snapshot is for.
-- ---------------------------------------------------------------------------------------------

-- A Level (1–10) and a handicap index (0–54) are two different scales and travel in two columns, so
-- neither can be mistaken for the other: `level_snapshot` is the Level XIX worked out, `index_snapshot`
-- is the index the player entered themselves. B.4.4 turns each into strokes its own way, and the index
-- wins when there is one.
alter table xix.players add column if not exists index_snapshot numeric;

create or replace function xix.snapshot_level()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
declare p xix.profiles;
begin
  if new.profile_id is not null and new.level_snapshot is null and new.index_snapshot is null then
    select * into p from xix.profiles x where x.id = new.profile_id;
    new.level_snapshot := p.level_auto;
    new.index_snapshot := p.level_index;
  end if;
  return new;
end;
$$;

drop trigger if exists players_snapshot_level on xix.players;
create trigger players_snapshot_level before insert or update of profile_id on xix.players
  for each row execute function xix.snapshot_level();

-- The engine takes both, and applies the index in preference (B.4.4). Until now round_input sent only
-- the Level, so an entered index never reached the scoring at all.
create or replace function xix.round_input(round_id uuid)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare r xix.rounds; out jsonb;
begin
  select * into r from xix.rounds x where x.id = round_input.round_id;
  if not found then
    raise exception 'round not found' using errcode = 'P0002';
  end if;
  -- Inside a security-definer function current_user is the owner, so only the JWT role can be trusted.
  if auth.role() is distinct from 'service_role' and not xix.is_round_member(r.id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'holes', r.holes,
    'par', (select coalesce(jsonb_agg(ch.par order by h.n), '[]'::jsonb)
              from generate_series(1, r.holes) h(n)
              left join xix.course_holes ch on ch.course_id = r.course_id and ch.hole = h.n),
    'strokeIndex', (select coalesce(jsonb_agg(ch.stroke_index order by h.n), '[]'::jsonb)
              from generate_series(1, r.holes) h(n)
              left join xix.course_holes ch on ch.course_id = r.course_id and ch.hole = h.n),
    'players', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', p.id, 'name', p.display_name, 'level', p.level_snapshot, 'index', p.index_snapshot,
                  'extras', case when p.left_at is not null
                                 then jsonb_build_object('leftAfterHole', coalesce((select max(s.hole) from xix.scores s where s.player_id = p.id), 0))
                                 else null end) order by p.seat), '[]'::jsonb)
                from xix.players p where p.round_id = r.id),
    'scores', (select coalesce(jsonb_object_agg(p.id, (
                  select coalesce(jsonb_agg(case when s.picked_up then to_jsonb('PU'::text) else to_jsonb(s.strokes) end order by h.n), '[]'::jsonb)
                    from generate_series(1, r.holes) h(n)
                    left join xix.scores s on s.round_id = r.id and s.player_id = p.id and s.hole = h.n)), '{}'::jsonb)
                from xix.players p where p.round_id = r.id),
    'games', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', g.id, 'format', g.format, 'options', g.options,
                  'players', (select coalesce(jsonb_agg(gp.player_id order by pl.seat), '[]'::jsonb)
                                from xix.game_players gp join xix.players pl on pl.id = gp.player_id where gp.game_id = g.id),
                  'sides', (select jsonb_object_agg(gp.player_id, gp.side) from xix.game_players gp where gp.game_id = g.id and gp.side is not null))
                  order by g.created_at, g.id), '[]'::jsonb)
                from xix.games g where g.round_id = r.id),
    'callouts', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', c.id, 'hole', c.hole, 'kind', c.kind, 'caller', c.caller_id, 'targets', to_jsonb(c.target_ids), 'params', c.params,
                  'responses', (select coalesce(jsonb_object_agg(cr.player_id, cr.action), '{}'::jsonb) from xix.callout_responses cr where cr.callout_id = c.id))
                  order by c.created_at, c.id), '[]'::jsonb)
                from xix.callouts c where c.round_id = r.id)
  ) into out;
  return out;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 3b. A round starts counting the moment another player confirms it.
--
-- PRD 8.11: "Results count toward rankings when confirmed by at least one other player in the round;
-- auto-confirm after 48 hours." Only the second half of that existed — xix.auto_confirm's nightly
-- sweep — so a round everybody had confirmed still waited two days to count. An objection freezes it
-- again, which is what "I object" means (PRD 8.11).
--
-- Changing your mind is allowed: confirm_round does nothing on a repeat, but an objection arriving
-- later must still freeze, so this fires on update too.
-- ---------------------------------------------------------------------------------------------

create or replace function xix.count_round_on_confirmation()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
begin
  if new.action = 'object' then
    update xix.rounds set counted_at = null where id = new.round_id;
    return new;
  end if;
  update xix.rounds r
     set counted_at = coalesce(r.counted_at, now())
   where r.id = new.round_id
     and r.status = 'ended'
     and exists (select 1 from xix.confirmations c
                  where c.round_id = r.id and c.action = 'confirm' and c.profile_id <> r.owner_id)
     and not exists (select 1 from xix.confirmations c where c.round_id = r.id and c.action = 'object');
  return new;
end;
$$;

drop trigger if exists confirmations_count_round on xix.confirmations;
create trigger confirmations_count_round after insert or update on xix.confirmations
  for each row execute function xix.count_round_on_confirmation();

-- ---------------------------------------------------------------------------------------------
-- 4. Rivalry: the head-to-head, from the rounds the two of you actually shared.
-- ---------------------------------------------------------------------------------------------

create or replace function xix.rivalry(other_profile uuid)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare me uuid := xix.require_auth(); out jsonb;
begin
  if other_profile = me then
    raise exception 'a rivalry needs two people' using errcode = '22023';
  end if;
  with shared as (
    select r.id as round_id, r.played_on, c.name as course, res.payload,
           mine.id as my_player, theirs.id as their_player
      from xix.rounds r
      join xix.players mine on mine.round_id = r.id and mine.profile_id = me
      join xix.players theirs on theirs.round_id = r.id and theirs.profile_id = other_profile
      join xix.results res on res.round_id = r.id
      left join xix.courses c on c.id = r.course_id
     where r.counted_at is not null and res.payload ->> 'status' = 'complete'
  ),
  scored as (
    select s.*,
           (s.payload -> 'perPlayer' -> s.my_player::text ->> 'gross')::integer as my_gross,
           (s.payload -> 'perPlayer' -> s.their_player::text ->> 'gross')::integer as their_gross
      from shared s
  )
  select jsonb_build_object(
    'me', (select display_name from xix.profiles where id = me),
    'them', (select display_name from xix.profiles where id = other_profile),
    'rounds', (select count(*) from scored),
    'my_wins', (select count(*) from scored where my_gross < their_gross),
    'their_wins', (select count(*) from scored where their_gross < my_gross),
    'halved', (select count(*) from scored where my_gross = their_gross),
    -- Medals the two of you won off each other, either way round.
    'my_medals', (select coalesce(jsonb_agg(jsonb_build_object('key', m.key, 'round_id', m.round_id, 'context', m.context) order by m.created_at desc), '[]'::jsonb)
                    from xix.medals m where m.profile_id = me and m.opponent_profile_id = other_profile),
    'their_medals', (select coalesce(jsonb_agg(jsonb_build_object('key', m.key, 'round_id', m.round_id, 'context', m.context) order by m.created_at desc), '[]'::jsonb)
                    from xix.medals m where m.profile_id = other_profile and m.opponent_profile_id = me),
    -- Callouts between you: how many each signed and ducked.
    'i_signed', (select count(*) from shared s join xix.callouts co on co.round_id = s.round_id
                  join xix.callout_responses cr on cr.callout_id = co.id and cr.player_id = s.my_player
                 where co.caller_id = s.their_player and cr.action = 'signed'),
    'i_ducked', (select count(*) from shared s join xix.callouts co on co.round_id = s.round_id
                  join xix.callout_responses cr on cr.callout_id = co.id and cr.player_id = s.my_player
                 where co.caller_id = s.their_player and cr.action = 'ducked'),
    'they_signed', (select count(*) from shared s join xix.callouts co on co.round_id = s.round_id
                     join xix.callout_responses cr on cr.callout_id = co.id and cr.player_id = s.their_player
                    where co.caller_id = s.my_player and cr.action = 'signed'),
    'they_ducked', (select count(*) from shared s join xix.callouts co on co.round_id = s.round_id
                     join xix.callout_responses cr on cr.callout_id = co.id and cr.player_id = s.their_player
                    where co.caller_id = s.my_player and cr.action = 'ducked'),
    -- The last five, with the stickers actually thrown in them (PRD 8.18).
    'last_five', (select coalesce(jsonb_agg(x order by x ->> 'played_on' desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'round_id', s.round_id, 'played_on', s.played_on, 'course', s.course,
          'my_gross', s.my_gross, 'their_gross', s.their_gross,
          'outcome', case when s.my_gross < s.their_gross then 'W'
                          when s.their_gross < s.my_gross then 'L' else 'H' end,
          'stickers', (select coalesce(jsonb_agg(distinct st.sticker_key), '[]'::jsonb)
                         from xix.stickers st
                        where st.round_id = s.round_id
                          and (st.target_player_id in (s.my_player, s.their_player)
                            or st.sender_player_id in (s.my_player, s.their_player)))
        ) as x
          from scored s order by s.played_on desc limit 5) last)
  ) into out;
  return out;
end;
$$;

-- Who you could have a rivalry with: people you have shared a counted round with, most recent first.
create or replace function xix.rivals()
returns table (profile_id uuid, display_name text, rounds integer, last_played date)
language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare me uuid := xix.require_auth();
begin
  return query
  select theirs.profile_id, pr.display_name, count(*)::integer, max(r.played_on)
    from xix.rounds r
    join xix.players mine on mine.round_id = r.id and mine.profile_id = me
    join xix.players theirs on theirs.round_id = r.id and theirs.profile_id is not null and theirs.profile_id <> me
    join xix.profiles pr on pr.id = theirs.profile_id
   where r.counted_at is not null
   group by theirs.profile_id, pr.display_name
   order by max(r.played_on) desc
   limit 50;
end;
$$;

revoke execute on function xix.refresh_rankings() from public, anon, authenticated;
revoke execute on function xix.create_crew(text), xix.crew_preview(text), xix.join_crew(text), xix.leave_crew(uuid),
                          xix.rankings(text, text, uuid), xix.pending_rounds(), xix.rivalry(uuid), xix.rivals()
  from public, anon;
grant execute on function xix.create_crew(text), xix.crew_preview(text), xix.join_crew(text), xix.leave_crew(uuid),
                         xix.rankings(text, text, uuid), xix.pending_rounds(), xix.rivalry(uuid), xix.rivals()
  to authenticated;
grant execute on function xix.refresh_rankings() to service_role;

-- Nightly, after auto_confirm has had its say. Same guard as 0011: only when pg_cron is there.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('xix-refresh-rankings', '20 3 * * *', 'select xix.refresh_rankings()');
  end if;
end;
$$;
