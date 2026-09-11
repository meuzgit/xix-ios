-- 0011: triggers (Build Doc 2 A.5). profiles_from_auth lives in 0001 with the profiles table.

-- scores_touch_updated_at: server last-write-wins key.
create or replace function xix.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger scores_touch_updated_at before insert or update on xix.scores
  for each row execute function xix.touch_updated_at();

-- callouts_close_on_score: a participant's score closes the hole to responses.
-- A callout still open (nobody signed) becomes expired; a live one keeps its signatures for the engine.
create or replace function xix.close_callouts_on_score()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
begin
  update xix.callouts c
     set closed_at = now(),
         status = case when c.status = 'open' then 'expired' else c.status end
   where c.round_id = new.round_id and c.hole = new.hole and c.closed_at is null
     and (c.caller_id = new.player_id or new.player_id = any (c.target_ids));
  return new;
end;
$$;
create trigger callouts_close_on_score after insert or update on xix.scores
  for each row execute function xix.close_callouts_on_score();

-- callout_responses: the responder must be a target of an open callout; a signature makes it live.
create or replace function xix.callout_response_guard()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
declare c xix.callouts;
begin
  select * into c from xix.callouts x where x.id = new.callout_id;
  if not found then
    raise exception 'callout not found' using errcode = 'P0002';
  end if;
  if not (new.player_id = any (c.target_ids)) then
    raise exception 'only a target may respond' using errcode = '42501';
  end if;
  if c.closed_at is not null then
    raise exception 'the hole is closed to responses' using errcode = '55000';
  end if;
  if new.action = 'signed' and c.status = 'open' then
    update xix.callouts x set status = 'live' where x.id = c.id;
  end if;
  return new;
end;
$$;
create trigger callout_responses_guard before insert on xix.callout_responses
  for each row execute function xix.callout_response_guard();

-- stickers_rate_limit: reject the 4th per (round, hole, sender).
create or replace function xix.stickers_rate_limit()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
begin
  if (select count(*) from xix.stickers x
       where x.round_id = new.round_id and x.hole = new.hole and x.sender_player_id = new.sender_player_id) >= 3 then
    raise exception 'three stickers per hole' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger stickers_rate_limit before insert on xix.stickers
  for each row execute function xix.stickers_rate_limit();

-- enqueue_engine: any change that can move a result asks for an engine run (deduplicated per round).
create or replace function xix.enqueue_engine_on_change()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
declare rid uuid;
begin
  if tg_table_name = 'callout_responses' then
    select c.round_id into rid from xix.callouts c where c.id = new.callout_id;
  else
    rid := new.round_id;
  end if;
  if rid is not null then
    perform xix.enqueue_engine_run(rid);
  end if;
  return new;
end;
$$;
create trigger enqueue_engine after insert or update on xix.scores for each row execute function xix.enqueue_engine_on_change();
create trigger enqueue_engine after insert or update on xix.games for each row execute function xix.enqueue_engine_on_change();
create trigger enqueue_engine after insert or update on xix.game_players for each row execute function xix.enqueue_engine_on_change();
create trigger enqueue_engine after insert or update on xix.callouts for each row execute function xix.enqueue_engine_on_change();
create trigger enqueue_engine after insert or update on xix.callout_responses for each row execute function xix.enqueue_engine_on_change();

-- auto_confirm: rounds ended more than 48 hours ago with no objection count automatically.
create or replace function xix.auto_confirm()
returns integer language plpgsql security definer set search_path = xix, pg_temp as $$
declare n integer;
begin
  with done as (
    update xix.rounds r
       set counted_at = now()
     where r.status = 'ended' and r.counted_at is null and r.ended_at < now() - interval '48 hours'
       and not exists (select 1 from xix.confirmations c where c.round_id = r.id and c.action = 'object')
     returning 1)
  select count(*) into n from done;
  return n;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('xix_auto_confirm', '0 3 * * *', $cron$select xix.auto_confirm()$cron$);
  end if;
end;
$$;
