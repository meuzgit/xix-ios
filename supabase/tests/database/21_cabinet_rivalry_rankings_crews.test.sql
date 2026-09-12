-- 0021: medals become shared with the people you played them against; crews get a code and their
-- three RPCs; rankings and the rivalry answer only for the caller, and only about rounds that count.
begin;
create extension if not exists pgtap with schema extensions;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'nobody@xix.local', '{}', '{"display_name":"Nobody"}', now(), now(), '', '', '', '');
insert into xix.profiles (id, display_name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Nobody');

create temp table ids as select
  '11111111-1111-4111-8111-111111111111'::uuid as ray,
  '22222222-2222-4222-8222-222222222222'::uuid as dave,
  '33333333-3333-4333-8333-333333333333'::uuid as mo,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as nobody,
  '66666666-6666-4666-8666-666666666666'::uuid as round;
do $$ begin execute format('grant select on all tables in schema %I to authenticated', (select nspname from pg_namespace where oid = pg_my_temp_schema())); end $$;

-- A medal each, from the round they played together.
insert into xix.medals (profile_id, round_id, key, opponent_profile_id)
select ray, round, 'nassau_front', dave from ids on conflict do nothing;
insert into xix.medals (profile_id, round_id, key, opponent_profile_id)
select dave, round, 'skins_two', ray from ids on conflict do nothing;

select plan(34);

-- 1. Medals: a rivalry has two sides, and neither is visible to a stranger.
select pg_temp.as_user((select ray from ids));
select is((select count(*)::int from xix.medals), 2, 'a player sees their own medals and their opponent''s from that round');
select pg_temp.as_user((select nobody from ids));
select is((select count(*)::int from xix.medals), 0, 'somebody who was not there sees none of them');

-- 2. Crews: create, preview, join, leave.
select pg_temp.as_user((select ray from ids));
create temp table crew as select * from xix.create_crew('Sunday Foursome');
do $$ begin execute format('grant select on all tables in schema %I to authenticated', (select nspname from pg_namespace where oid = pg_my_temp_schema())); end $$;
select is((select owner_id from crew), (select ray from ids), 'the maker owns it');
select isnt((select join_code from crew), null, 'and it has a code to share');
select is((select count(*)::int from xix.crew_members m where m.crew_id = (select id from crew)), 1, 'the maker is in it');
select throws_ok($$select xix.create_crew('   ')$$, '22023', null, 'a crew needs a name');

select pg_temp.as_user((select dave from ids));
select is(xix.crew_preview((select join_code from crew)) ->> 'name', 'Sunday Foursome', 'the code shows the crew before joining');
select is((xix.crew_preview((select join_code from crew)) ->> 'mine')::boolean, false, 'and says you are not in it yet');
select throws_ok($$select xix.crew_preview('NOPE99')$$, 'P0002', null, 'an unknown code is refused');
select lives_ok($$select xix.join_crew((select join_code from crew))$$, 'joining by code');
select is((select count(*)::int from xix.crew_members m where m.crew_id = (select id from crew)), 2, 'now two of them');
select lives_ok($$select xix.leave_crew((select id from crew))$$, 'and leaving again');
select is((select count(*)::int from xix.crew_members m where m.crew_id = (select id from crew)), 0,
          'having left, he cannot see the crew at all — a crew is private to its members');
select pg_temp.as_postgres();
select is((select count(*)::int from xix.crew_members m where m.crew_id = (select id from crew)), 1, 'and one row is left: the owner''s');

select pg_temp.as_user((select ray from ids));
select throws_ok($$select xix.leave_crew((select id from crew))$$, '55000', null, 'the owner cannot leave their own crew');

-- 2b. A Level is frozen onto the row when somebody joins the round.
select pg_temp.as_postgres();
update xix.profiles set level_auto = 6.5 where id = (select dave from ids);
insert into xix.rounds (id, owner_id, status, join_code)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7', (select ray from ids), 'live', 'LEVEL1');
insert into xix.players (round_id, profile_id, display_name, seat, claimed_at)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7', (select dave from ids), 'Dave', 0, now());
select is((select level_snapshot from xix.players
            where round_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7'), 6.5::numeric,
          'the player''s Level is frozen onto the row as they join');
insert into xix.players (round_id, display_name, seat)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7', 'Guest', 1);
select is((select level_snapshot from xix.players
            where round_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7' and display_name = 'Guest'), null,
          'a guest with no account has none, and none is invented');
-- An entered index is a different scale from a Level and travels in its own column, so neither can be
-- read as the other; the engine takes both and prefers the index (B.4.4).
update xix.profiles set level_index = 12 where id = (select mo from ids);
insert into xix.players (round_id, profile_id, display_name, seat)
  values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7', (select mo from ids), 'Mo', 2);
select is((select index_snapshot from xix.players
            where round_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7' and display_name = 'Mo'), 12::numeric,
          'the index is frozen as an index');
select pg_temp.as_user((select ray from ids));
select is((select (round_input -> 'players' -> 2 -> 'index')::numeric from xix.round_input('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7') as round_input), 12::numeric,
          'and reaches the engine as one');
select pg_temp.as_postgres();
update xix.profiles set level_auto = 2 where id = (select dave from ids);
select is((select level_snapshot from xix.players
            where round_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7' and display_name = 'Dave'), 6.5::numeric,
          'and it stays as it was on the day, whatever their Level does later');
select pg_temp.as_user((select ray from ids));

-- 3. Rankings: the metrics are a closed set, and a crew board needs membership.
select throws_ok($$select * from xix.rankings('handsomeness', 'all')$$, '22023', null, 'no such metric');
select throws_ok($$select * from xix.rankings('birdies', 'decade')$$, '22023', null, 'no such window');
select pg_temp.as_user((select nobody from ids));
select throws_ok($$select * from xix.rankings('birdies', 'all', (select id from crew))$$, '42501', null,
                 'a crew board is private to its crew');

-- 4. Rankings count only rounds that count.
select pg_temp.as_postgres();
select is((select count(*)::int from xix.ranking_entries), 0, 'nothing is ranked before a round is counted');
select is(xix.refresh_rankings(), 0, 'and the job finds nothing to write');

-- 5. The rivalry needs two people, and reads only shared counted rounds.
select pg_temp.as_user((select ray from ids));
select throws_ok($$select xix.rivalry((select ray from ids))$$, '22023', null, 'a rivalry needs two people');
select is(xix.rivalry((select dave from ids)) ->> 'rounds', '0', 'an uncounted round is in no rivalry');
select is(xix.rivalry((select dave from ids)) ->> 'them', 'Dave', 'but the other player is named');

-- 6. A round counts as soon as another player confirms it, and an objection freezes it again.
select pg_temp.as_postgres();
update xix.rounds set status = 'ended', ended_at = now(), counted_at = null where id = (select round from ids);
delete from xix.confirmations where round_id = (select round from ids);
select pg_temp.as_user((select ray from ids));
select lives_ok($$select xix.confirm_round((select round from ids), 'confirm')$$, 'the owner confirms their own round');
select pg_temp.as_postgres();
select is((select counted_at from xix.rounds where id = (select round from ids)), null,
          'which on its own counts for nothing — it has to be somebody else');
select pg_temp.as_user((select dave from ids));
select lives_ok($$select xix.confirm_round((select round from ids), 'confirm')$$, 'another player confirms it');
select pg_temp.as_postgres();
select isnt((select counted_at from xix.rounds where id = (select round from ids)), null,
            'and it counts at once, rather than waiting out the 48 hours');
select pg_temp.as_postgres();
insert into xix.confirmations (round_id, profile_id, action)
  values ((select round from ids), (select nobody from ids), 'object')
  on conflict (round_id, profile_id) do update set action = 'object';
select is((select counted_at from xix.rounds where id = (select round from ids)), null,
          'an objection freezes it again');

-- 7. The job itself is nobody's to call.
select pg_temp.as_user((select ray from ids));
select throws_ok($$select xix.refresh_rankings()$$, '42501', null, 'the ranking job is not callable by a player');

select * from finish();
rollback;
