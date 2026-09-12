-- engine webhook (0018): the trigger exists on xix.engine_queue and one queue insert issues one
-- net.http_post to the engine with the round id in the body and the Vault key in the header.
begin;
create extension if not exists pgtap with schema extensions;
create temp table ids as select '66666666-6666-4666-8666-666666666666'::uuid as round;
delete from xix.engine_queue;

select plan(7);

select has_function('xix', 'notify_engine_webhook', 'the webhook function exists');
select has_trigger('xix', 'engine_queue', 'engine_queue_webhook', 'and is attached to engine_queue');
select is((select count(*)::int from vault.decrypted_secrets where name = 'xix_service_role_key'), 1, 'the service-role key is in Vault');

create temp table before as select count(*) as n from net.http_request_queue;
insert into xix.engine_queue (round_id) values ((select round from ids));
select is((select count(*)::int from net.http_request_queue) - (select n::int from before), 1, 'one queue insert issues one http_post');
select ok((select url from net.http_request_queue order by id desc limit 1) like '%/functions/v1/xix-engine', 'to the engine function');
select is((select convert_from(body, 'utf8')::jsonb -> 'record' ->> 'round_id' from net.http_request_queue order by id desc limit 1), (select round::text from ids), 'with the round id in the body');
select ok((select headers ->> 'Authorization' from net.http_request_queue order by id desc limit 1) like 'Bearer %', 'and a bearer token from Vault');

select * from finish();
rollback;
