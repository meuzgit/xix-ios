-- 0019: a join code resolves for an ended round so a guest can claim their row from the result link.
begin;
create extension if not exists pgtap with schema extensions;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'nobody@xix.local', '{}', '{"display_name":"Nobody"}', now(), now(), '', '', '', '');
create temp table fresh as select
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'::uuid as round, '11111111-1111-4111-8111-111111111111'::uuid as ray,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as nobody,
  'cccccccc-cccc-4ccc-8ccc-ccccccccccd0'::uuid as ray_row, 'cccccccc-cccc-4ccc-8ccc-ccccccccccd2'::uuid as guest_row;
insert into xix.rounds (id, owner_id, status, join_code, ended_at) select round, ray, 'ended', 'ENDED1', now() from fresh;
insert into xix.players (id, round_id, profile_id, display_name, seat, claimed_at) select ray_row, round, ray, 'Ray', 0, now() from fresh;
insert into xix.players (id, round_id, display_name, seat) select guest_row, round, 'Tess', 1 from fresh;
do $$ begin execute format('grant select on all tables in schema %I to authenticated', (select nspname from pg_namespace where oid = pg_my_temp_schema())); end $$;

select plan(5);

select pg_temp.as_user((select nobody from fresh));
select is((select id from xix.join_round('ENDED1')), (select round from fresh), 'join by code finds the ended round');
select is(xix.joinable_rows('ENDED1') -> 'round' ->> 'status', 'ended', 'the join screen says the round has ended');
select is((select jsonb_agg(p ->> 'display_name') from jsonb_array_elements(xix.joinable_rows('ENDED1') -> 'players') p where (p ->> 'claimable')::boolean), '["Tess"]'::jsonb, 'the guest row is still claimable');
select lives_ok($$select xix.claim_row((select round from fresh), (select guest_row from fresh))$$, 'and can be claimed after the round ended');
select throws_ok($$select xix.join_round('NOPE99')$$, 'P0002', null, 'an unknown code is still refused');

select * from finish();
rollback;
