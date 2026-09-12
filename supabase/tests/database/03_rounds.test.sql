-- rounds: members read; join by code through the RPC; owner writes; delete only in setup
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

create temp table newround (id uuid, join_code text);
select pg_temp.share();
select pg_temp.as_user((select ray from ids));
select is((select count(*)::int from xix.rounds), 1, 'the owner sees the round');
select lives_ok($$with i as (insert into xix.rounds (owner_id) values ((select ray from ids)) returning id, join_code) insert into newround select * from i$$, 'a signed-in user creates a round they own');
select throws_ok($$insert into xix.rounds (owner_id) values ((select dave from ids))$$, '42501', null, 'but not one owned by someone else');
select is(pg_temp.affected($$update xix.rounds set played_on = '2026-09-10' where id = (select round from ids)$$), 1, 'owner updates');
select is(pg_temp.affected($$delete from xix.rounds where id = (select round from ids)$$), 0, 'owner cannot delete an ended round');
select is(pg_temp.affected($$delete from xix.rounds where id = (select id from newround)$$), 1, 'owner deletes a round still in setup');
select pg_temp.as_user((select dave from ids));
select is((select count(*)::int from xix.rounds), 1, 'a member sees the round');
select is(pg_temp.affected($$update xix.rounds set played_on = '2026-09-10' where id = (select round from ids)$$), 0, 'a member cannot update it');
select pg_temp.as_user((select nobody from ids));
select is((select count(*)::int from xix.rounds), 0, 'a non-member sees nothing');
select is((select id from xix.join_round('FRSRVW')), (select round from ids), 'join by code resolves an ended round (result links, 0019)');
select is((select count(*)::int from xix.rounds), 0, 'without granting membership: the non-member still sees nothing');

select * from finish();
rollback;
