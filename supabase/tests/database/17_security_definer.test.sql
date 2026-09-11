-- Every SECURITY DEFINER function in xix is listed here, and every one that acts on a round refuses a
-- signed-in non-member. A new function fails this test until it is added to the list with its refusal.
-- Lesson from step 2: inside a security-definer body current_user is the owner, so only auth.uid() and
-- auth.role() can be trusted for authorisation.
begin;
create extension if not exists pgtap with schema extensions;
create function pg_temp.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'nobody@xix.local', '{}', '{"display_name":"Nobody"}', now(), now(), '', '', '', '');
insert into xix.profiles (id, display_name) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Nobody');
create temp table ids as select
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as nobody, '66666666-6666-4666-8666-666666666666'::uuid as round,
  '77777777-7777-4777-8777-777777777771'::uuid as ray_row, '77777777-7777-4777-8777-777777777772'::uuid as dave_row,
  '99999999-9999-4999-8999-999999999991'::uuid as callout, '88888888-8888-4888-8888-888888888882'::uuid as skins;
do $$ begin execute format('grant select on all tables in schema %I to authenticated', (select nspname from pg_namespace where oid = pg_my_temp_schema())); end $$;

select plan(26);

-- 1. The census. Trigger functions are excluded (they cannot be called directly).
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'xix'::regnamespace and p.prosecdef and p.prorettype <> 'trigger'::regtype),
  array[
    'add_guest', 'apply_engine_result', 'auto_confirm', 'claim_row', 'confirm_round', 'create_callout', 'end_round',
    'engine_run_failed', 'enqueue_engine_run', 'ensure_profile', 'enter_score', 'is_crew_member', 'is_crew_owner',
    'is_own_player_row', 'is_round_member', 'is_round_owner', 'join_round', 'joinable_rows', 'leave_round', 'my_player_id',
    'respond_callout', 'round_input', 'send_sticker', 'set_games', 'shares_round_or_crew', 'update_level_auto'
  ]::text[],
  'every security-definer function is accounted for below');

select pg_temp.as_user((select nobody from ids));

-- 2. Round RPCs refuse a non-member.
select throws_ok($$select xix.add_guest((select round from ids), 'X')$$, '42501', null, 'add_guest');
select throws_ok($$select xix.set_games((select round from ids), '[]'::jsonb)$$, '42501', null, 'set_games');
select throws_ok($$select xix.enter_score((select round from ids), (select ray_row from ids), 1::smallint, 4::smallint, false, now())$$, '42501', null, 'enter_score');
select throws_ok($$select xix.create_callout((select round from ids), 1::smallint, 'target', array[(select ray_row from ids)], '{}'::jsonb)$$, '42501', null, 'create_callout');
select throws_ok($$select xix.respond_callout((select callout from ids), 'signed')$$, '42501', null, 'respond_callout');
select throws_ok($$select xix.send_sticker((select round from ids), 1::smallint, (select ray_row from ids), 'YIKES')$$, '42501', null, 'send_sticker');
select throws_ok($$select xix.end_round((select round from ids))$$, '42501', null, 'end_round');
select throws_ok($$select xix.leave_round((select round from ids))$$, '42501', null, 'leave_round');
select throws_ok($$select xix.confirm_round((select round from ids), 'confirm')$$, '42501', null, 'confirm_round');
select throws_ok($$select xix.round_input((select round from ids))$$, '42501', null, 'round_input');
select throws_ok($$select xix.claim_row((select round from ids), (select ray_row from ids))$$, 'P0002', null, 'claim_row refuses a row that is not free');

-- 3. Engine and internal functions are not callable by authenticated users at all.
select throws_ok($$select xix.apply_engine_result((select round from ids), 1, '{}'::jsonb)$$, '42501', null, 'apply_engine_result');
select throws_ok($$select xix.engine_run_failed((select round from ids), 'x')$$, '42501', null, 'engine_run_failed');
select throws_ok($$select xix.update_level_auto((select nobody from ids))$$, '42501', null, 'update_level_auto (no execute grant)');
select throws_ok($$select xix.enqueue_engine_run((select round from ids))$$, '42501', null, 'enqueue_engine_run (no execute grant)');
select throws_ok($$select xix.auto_confirm()$$, '42501', null, 'auto_confirm (cron only)');

-- 4. Read-only helpers answer false or nothing for a non-member.
select is(xix.is_round_member((select round from ids)), false, 'is_round_member');
select is(xix.is_round_owner((select round from ids)), false, 'is_round_owner');
select is(xix.my_player_id((select round from ids)), null, 'my_player_id');
select is(xix.is_own_player_row((select round from ids), (select ray_row from ids)), false, 'is_own_player_row');
select is(xix.shares_round_or_crew('11111111-1111-4111-8111-111111111111'), false, 'shares_round_or_crew');
select is(xix.is_crew_member('ffffffff-ffff-4fff-8fff-ffffffffffff'), false, 'is_crew_member');
select is(xix.is_crew_owner('ffffffff-ffff-4fff-8fff-ffffffffffff'), false, 'is_crew_owner');

-- 5. Allowed by design: ensure_profile creates only the caller's own row; join_round returns a round
--    for a code without adding membership (an ended round is refused).
select throws_ok($$select xix.join_round('FRSRVW')$$, 'P0002', null, 'join_round: ended round is not joinable; membership is never granted here');
select throws_ok($$select * from xix.joinable_rows('FRSRVW')$$, 'P0002', null, 'joinable_rows: same rule, and only unclaimed rows of an open round are ever returned');

select * from finish();
rollback;
