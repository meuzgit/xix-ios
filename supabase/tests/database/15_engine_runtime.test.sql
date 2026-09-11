-- engine runtime RPCs (0013): round_input for members and the service role; apply_engine_result and
-- engine_run_failed for the service role only; five failures move a round to the dead-letter table.
begin;
create extension if not exists pgtap with schema extensions;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
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
  '22222222-2222-4222-8222-222222222222'::uuid as dave, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as nobody,
  '66666666-6666-4666-8666-666666666666'::uuid as round, '77777777-7777-4777-8777-777777777771'::uuid as ray_row;
do $$ begin execute format('grant select on all tables in schema %I to authenticated, service_role', (select nspname from pg_namespace where oid = pg_my_temp_schema())); end $$;
delete from xix.engine_queue;

select plan(12);

select pg_temp.as_user((select dave from ids));
select is((xix.round_input((select round from ids)) ->> 'holes')::int, 18, 'a member reads the round as RoundInput');
select is(jsonb_array_length(xix.round_input((select round from ids)) -> 'players'), 4, 'with every player');
select is(xix.round_input((select round from ids)) -> 'scores' -> (select ray_row from ids)::text -> 0, '5'::jsonb, 'scores keyed by player row in hole order');
select is(xix.round_input((select round from ids)) -> 'callouts' -> 1 -> 'responses' -> '77777777-7777-4777-8777-777777777772', '"ducked"'::jsonb, 'callout responses per target');
select throws_ok($$select xix.apply_engine_result((select round from ids), 1, '{"status":"complete","medals":[]}'::jsonb)$$, '42501', null, 'a member cannot write results');
select pg_temp.as_user((select nobody from ids));
select throws_ok($$select xix.round_input((select round from ids))$$, '42501', null, 'a non-member cannot read the round');

select pg_temp.as_service();
select lives_ok($$select xix.round_input((select round from ids))$$, 'the service role reads any round');
insert into xix.engine_queue (round_id) values ((select round from ids));
select lives_ok($$select xix.apply_engine_result((select round from ids), 1, jsonb_build_object('status', 'complete', 'engineVersion', 1,
  'medals', jsonb_build_array(jsonb_build_object('profile', (select ray_row from ids), 'key', 'stroke_low_gross', 'opponent', null))))$$,
  'the service role stores a result');
select is((select count(*)::int from xix.engine_queue), 0, 'and the queue row is consumed');
select lives_ok($$select xix.apply_engine_result((select round from ids), 1, jsonb_build_object('status', 'complete', 'engineVersion', 1,
  'medals', jsonb_build_array(jsonb_build_object('profile', (select ray_row from ids), 'key', 'stroke_low_gross', 'opponent', null))))$$,
  'a second run with the same medal');
select is((select count(*)::int from xix.medals where key = 'stroke_low_gross'), 1, 'awards it once');

insert into xix.engine_queue (round_id) values ((select round from ids));
select xix.engine_run_failed((select round from ids), 'boom') from generate_series(1, 5);
select is((select count(*)::int from xix.engine_dead_letter where round_id = (select round from ids)), 1, 'five failures move the round to the dead-letter table and off the queue');

select * from finish();
rollback;
