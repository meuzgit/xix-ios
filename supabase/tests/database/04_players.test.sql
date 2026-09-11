-- players: members read; owner writes any row; member edits own display_name only; owner deletes unclaimed rows
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

select plan(11);
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
select is((select count(*)::int from xix.players where round_id = (select round from ids)), 4, 'a member sees every player row');
select throws_ok($$insert into xix.players (round_id, display_name, seat) values ((select round from fresh), 'Extra', 3)$$, '42501', null, 'a member cannot add players');
select is(pg_temp.affected($$update xix.players set display_name = 'Davey' where id = (select dave_row from fresh)$$), 1, 'a member renames their own row');
select throws_ok($$update xix.players set seat = 3 where id = (select dave_row from fresh)$$, '42501', null, 'but may not change anything else on it');
select is(pg_temp.affected($$update xix.players set display_name = 'X' where id = (select ray_row from fresh)$$), 0, 'nor touch another row');
select is(pg_temp.affected($$delete from xix.players where id = (select guest_row from fresh)$$), 0, 'nor delete');
select pg_temp.as_user((select ray from ids));
select lives_ok($$insert into xix.players (round_id, display_name, seat) values ((select round from fresh), 'Extra', 3)$$, 'the owner adds a row');
select is(pg_temp.affected($$update xix.players set level_snapshot = 4 where id = (select dave_row from fresh)$$), 1, 'the owner edits any field on any row');
select is(pg_temp.affected($$delete from xix.players where id = (select dave_row from fresh)$$), 0, 'the owner cannot delete a claimed row');
select is(pg_temp.affected($$delete from xix.players where id = (select guest_row from fresh)$$), 1, 'but deletes an unclaimed one');
select pg_temp.as_user((select nobody from ids));
select is((select count(*)::int from xix.players), 0, 'a non-member sees no players');

select * from finish();
rollback;
