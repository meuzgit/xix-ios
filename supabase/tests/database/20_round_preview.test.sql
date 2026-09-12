-- 0020: round_preview answers anonymously with the landing page's fields and nothing else.
begin;
create extension if not exists pgtap with schema extensions;
create function pg_temp.as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end $$;
insert into xix.rounds (id, owner_id, course_id, status, join_code)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', '11111111-1111-4111-8111-111111111111',
        (select id from xix.courses where name = 'Fraserview' limit 1), 'live', 'PREVW1');
insert into xix.players (round_id, profile_id, display_name, seat, claimed_at)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', '11111111-1111-4111-8111-111111111111', 'Ray', 0, now());
insert into xix.players (round_id, display_name, seat) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', 'Tess', 1);
insert into xix.scores (round_id, player_id, hole, strokes, client_ts)
select 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2', id, 1, 4, now() from xix.players where round_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2' and seat = 0;

select plan(8);

select pg_temp.as_anon();
select is(xix.round_preview('prevw1') ->> 'course', 'Fraserview', 'anon reads the course name (code case-insensitive)');
select is(xix.round_preview('PREVW1') ->> 'owner', 'Ray', 'and the owner''s display name');
select is(xix.round_preview('PREVW1') -> 'players', '["Ray", "Tess"]'::jsonb, 'and the players'' display names in seat order');
select is((select array_agg(k order by k) from jsonb_object_keys(xix.round_preview('PREVW1')) k),
          array['course', 'holes', 'owner', 'played_on', 'players', 'region', 'status'],
          'exactly these fields: no ids, no scores, no games');
select is(xix.round_preview('NOPE99'), null, 'an unknown code answers null, not an error');
select throws_ok($$select xix.joinable_rows('PREVW1')$$, '42501', null, 'the join screen itself is still not anonymous');
select throws_ok($$select count(*) from xix.rounds$$, '42501', null, 'anon still cannot read the table directly');
select throws_ok($$select xix.join_round('PREVW1')$$, '42501', null, 'nor can anon join');

select * from finish();
rollback;
