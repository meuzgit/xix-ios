-- stickers: members read; sent through send_sticker with a cap of three per hole; the target marks played_at
begin;
create extension if not exists pgtap with schema extensions;

-- Act as a signed-in user (sets auth.uid() and the authenticated role for the rest of the transaction).
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
-- Temp tables are created as postgres; let the authenticated role read and write them.
create function pg_temp.share() returns void language plpgsql as $$
begin
  execute format('grant select, insert on all tables in schema %I to authenticated',
                 (select nspname from pg_namespace where oid = pg_my_temp_schema()));
end $$;
-- Rows affected by an update or delete (0 when RLS hides the row).
create function pg_temp.affected(sql text) returns int language plpgsql as $$
declare n int;
begin
  execute 'with u as (' || sql || ' returning 1) select count(*) from u' into n;
  return n;
end $$;
-- A signed-in user who is in no round and no crew.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'nobody@xix.local', '{}', '{"display_name":"Nobody"}', now(), now(), '', '', '', '');
insert into xix.profiles (id, display_name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Nobody');

-- Seeded ids (supabase/seed.sql)
create temp table ids as select
  '11111111-1111-4111-8111-111111111111'::uuid as ray, '22222222-2222-4222-8222-222222222222'::uuid as dave,
  '33333333-3333-4333-8333-333333333333'::uuid as mo,  '44444444-4444-4444-8444-444444444444'::uuid as tess,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as nobody,
  '66666666-6666-4666-8666-666666666666'::uuid as round,
  '77777777-7777-4777-8777-777777777771'::uuid as ray_row, '77777777-7777-4777-8777-777777777772'::uuid as dave_row,
  '77777777-7777-4777-8777-777777777773'::uuid as mo_row, '77777777-7777-4777-8777-777777777774'::uuid as tess_row,
  '55555555-5555-4555-8555-555555555555'::uuid as course;
select pg_temp.share();

select plan(10);
-- A fresh live round: Ray owns seat 0, Dave has claimed seat 1, seat 2 is an unclaimed guest.
create temp table fresh as select
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid as round,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc0'::uuid as ray_row, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid as dave_row,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'::uuid as guest_row;
insert into xix.rounds (id, owner_id, status, join_code) select round, (select ray from ids), 'live', 'FRESH2' from fresh;
insert into xix.players (id, round_id, profile_id, display_name, seat, claimed_at)
  select ray_row, round, (select ray from ids), 'Ray', 0, now() from fresh;
insert into xix.players (id, round_id, profile_id, display_name, seat, claimed_at)
  select dave_row, round, (select dave from ids), 'Dave', 1, now() from fresh;
insert into xix.players (id, round_id, display_name, seat) select guest_row, round, 'Guest', 2 from fresh;
select pg_temp.share();


select pg_temp.as_user((select dave from ids));
select lives_ok($$select xix.send_sticker((select round from fresh), 6::smallint, (select ray_row from fresh), 'YIKES')$$, 'a member sends a sticker');
select lives_ok($$select xix.send_sticker((select round from fresh), 6::smallint, (select ray_row from fresh), 'HAHAHA')$$, 'and a second');
select lives_ok($$select xix.send_sticker((select round from fresh), 6::smallint, (select ray_row from fresh), 'WASTED')$$, 'and a third');
select throws_ok($$select xix.send_sticker((select round from fresh), 6::smallint, (select ray_row from fresh), 'SNAKE')$$, '23514', null, 'the fourth on a hole is refused');
select throws_ok($$select xix.send_sticker((select round from fresh), 7::smallint, (select ray_row from fresh), 'CLUTCH', 'pro')$$, '42501', null, 'only the base pack is available for now');
select throws_ok($$insert into xix.stickers (round_id, hole, target_player_id, sender_player_id, sticker_key) values ((select round from fresh), 7, (select ray_row from fresh), (select dave_row from fresh), 'CLUTCH')$$, '42501', null, 'no direct insert');
select is(pg_temp.affected($$update xix.stickers set played_at = now() where round_id = (select round from fresh)$$), 0, 'the sender cannot mark it played');
select pg_temp.as_user((select ray from ids));
select is((select count(*)::int from xix.stickers where round_id = (select round from fresh)), 3, 'the target reads them');
select is(pg_temp.affected($$update xix.stickers set played_at = now() where round_id = (select round from fresh)$$), 3, 'and marks them played');
select throws_ok($$update xix.stickers set sticker_key = 'CLUTCH' where round_id = (select round from fresh)$$, '42501', null, 'but may change nothing else');

select * from finish();
rollback;
