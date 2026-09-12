-- 0018: the Database Webhook that runs the engine (Build Doc 2 B.2), as SQL because the dashboard's
-- webhook form lists only public tables. Every insert or update on xix.engine_queue posts the row to
-- xix-engine through pg_net, with the service-role key read from Vault (xix_service_role_key). The
-- function URL comes from Vault too (xix_engine_url) and defaults to the shared project's.
-- Update as well as insert: enqueue_engine_run upserts, so a round still queued after a failed run
-- only updates its row.

create extension if not exists pg_net with schema extensions;

create or replace function xix.notify_engine_webhook()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
declare key text; url text;
begin
  select decrypted_secret into key from vault.decrypted_secrets where name = 'xix_service_role_key' limit 1;
  select decrypted_secret into url from vault.decrypted_secrets where name = 'xix_engine_url' limit 1;
  if key is null then
    raise warning 'xix_service_role_key is not in Vault; engine run for % not requested', new.round_id;
    return new;
  end if;
  perform net.http_post(
    url := coalesce(url, 'https://zsipifaskpupjwfiinen.supabase.co/functions/v1/xix-engine'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || key),
    body := jsonb_build_object('type', tg_op, 'table', 'engine_queue', 'schema', 'xix',
                               'record', jsonb_build_object('round_id', new.round_id, 'requested_at', new.requested_at, 'attempts', new.attempts)),
    timeout_milliseconds := 30000);
  return new;
end;
$$;

revoke execute on function xix.notify_engine_webhook() from public, anon, authenticated;

create trigger engine_queue_webhook
  after insert or update on xix.engine_queue
  for each row execute function xix.notify_engine_webhook();
