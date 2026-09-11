-- claim_row: a signed-in user claims an unclaimed row once, and the claim enqueues an engine run so
-- medals earned before signing in appear immediately.
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
create temp table fresh as select
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid as round, '11111111-1111-4111-8111-111111111111'::uuid as ray,
  '22222222-2222-4222-8222-222222222222'::uuid as dave, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as nobody,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc0'::uuid as ray_row, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2'::uuid as guest_row;
insert into xix.rounds (id, owner_id, status, join_code) select round, ray, 'live', 'CLAIM1' from fresh;
insert into xix.players (id, round_id, profile_id, display_name, seat, claimed_at) select ray_row, round, ray, 'Ray', 0, now() from fresh;
insert into xix.players (id, round_id, display_name, seat) select guest_row, round, 'Guest', 2 from fresh;
do $$ begin execute format('grant select on all tables in schema %I to authenticated', (select nspname from pg_namespace where oid = pg_my_temp_schema())); end $$;
delete from xix.engine_queue;

select plan(11);

select pg_temp.as_user((select nobody from fresh));
select is((select count(*)::int from xix.profiles where id = (select nobody from fresh)), 0, 'no profile before the first XIX action');
select is((select id from xix.join_round('CLAIM1')), (select round from fresh), 'join by code finds the live round without membership');
select is((select array_agg(display_name) from xix.joinable_rows('CLAIM1')), array['Guest'], 'joinable_rows lists only the unclaimed rows');
select is((select count(*)::int from xix.profiles where id = (select nobody from fresh)), 1, 'the first RPC created their profile');
select lives_ok($$select xix.claim_row((select round from fresh), (select guest_row from fresh))$$, 'claims the guest row');
select is((select profile_id from xix.players where id = (select guest_row from fresh)), (select nobody from fresh), 'the row is theirs');
select pg_temp.as_postgres();
select is((select count(*)::int from xix.engine_queue where round_id = (select round from fresh)), 1, 'claiming enqueues an engine run for the round');
select pg_temp.as_user((select nobody from fresh));
select throws_ok($$select xix.claim_row((select round from fresh), (select ray_row from fresh))$$, '23505', null, 'cannot claim a second row in the same round');
select lives_ok($$select xix.leave_round((select round from fresh))$$, 'the claimant can leave the round');
-- Having left, they are no longer a member and RLS hides the row from them; read it as postgres.
select pg_temp.as_postgres();
select is((select left_at is not null from xix.players where id = (select guest_row from fresh)), true, 'left_at is set on their row');
select pg_temp.as_user((select dave from fresh));
select throws_ok($$select xix.claim_row((select round from fresh), (select guest_row from fresh))$$, 'P0002', null, 'a claimed row cannot be claimed again');

select * from finish();
rollback;
