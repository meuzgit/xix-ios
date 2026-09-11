-- 0010: RPCs (Build Doc 2 A.4). All SECURITY DEFINER; every one validates the caller's membership.

create or replace function xix.require_auth() returns uuid
language plpgsql stable as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  return auth.uid();
end;
$$;

-- Create the caller's profile from auth.users if it does not exist yet. Called by the client right after
-- the first Sign in with Apple and by every RPC below, so a profile always exists before anything
-- references it. The display name comes from the Apple credential's metadata and stays editable.
create or replace function xix.ensure_profile()
returns xix.profiles language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := xix.require_auth(); p xix.profiles;
begin
  insert into xix.profiles (id, display_name)
  select u.id, nullif(trim(coalesce(u.raw_user_meta_data ->> 'display_name', u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')), '')
    from auth.users u where u.id = me
  on conflict (id) do nothing;
  select * into p from xix.profiles x where x.id = me;
  if not found then
    raise exception 'no auth user for %', me using errcode = 'P0002';
  end if;
  return p;
end;
$$;

-- Returns the round for a join code without requiring membership; the client then calls claim_row.
create or replace function xix.join_round(code text)
returns xix.rounds language plpgsql security definer set search_path = xix, pg_temp as $$
declare r xix.rounds;
begin
  perform xix.ensure_profile();
  select * into r from xix.rounds where join_code = upper(trim(join_round.code)) and status in ('setup', 'live');
  if not found then
    raise exception 'no open round for that code' using errcode = 'P0002';
  end if;
  return r;
end;
$$;

-- Claim an unclaimed row as yourself; refused if you already have a row in the round.
create or replace function xix.claim_row(round_id uuid, player_id uuid)
returns xix.players language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; p xix.players;
begin
  if not exists (select 1 from xix.rounds r where r.id = claim_row.round_id and r.status in ('setup', 'live', 'ended')) then
    raise exception 'round not found' using errcode = 'P0002';
  end if;
  if exists (select 1 from xix.players x where x.round_id = claim_row.round_id and x.profile_id = me) then
    raise exception 'you already have a row in this round' using errcode = '23505';
  end if;
  update xix.players x
     set profile_id = me, claimed_at = now()
   where x.id = claim_row.player_id and x.round_id = claim_row.round_id and x.profile_id is null
   returning x.* into p;
  if not found then
    raise exception 'row is not available to claim' using errcode = 'P0002';
  end if;
  return p;
end;
$$;

-- Owner adds an unclaimed guest row at the next seat.
create or replace function xix.add_guest(round_id uuid, display_name text)
returns xix.players language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; next_seat int; p xix.players;
begin
  if not xix.is_round_owner(add_guest.round_id) then
    raise exception 'only the round owner can add players' using errcode = '42501';
  end if;
  select coalesce(max(seat) + 1, 0) into next_seat from xix.players x where x.round_id = add_guest.round_id;
  if next_seat > 3 then
    raise exception 'round is full' using errcode = '23514';
  end if;
  insert into xix.players (round_id, display_name, seat)
  values (add_guest.round_id, trim(add_guest.display_name), next_seat)
  returning * into p;
  return p;
end;
$$;

-- Owner replaces the round's games while no score exists on hole 1.
-- games: [{"id"?: uuid, "format": text, "options": {}, "players": [player_id], "sides": {player_id: 0|1}?}]
create or replace function xix.set_games(round_id uuid, games jsonb)
returns setof xix.games language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; g jsonb; gid uuid; pid text;
begin
  if not xix.is_round_owner(set_games.round_id) then
    raise exception 'only the round owner can set games' using errcode = '42501';
  end if;
  if exists (select 1 from xix.scores s where s.round_id = set_games.round_id and s.hole = 1) then
    raise exception 'games are locked once hole 1 has a score' using errcode = '55000';
  end if;
  if jsonb_typeof(set_games.games) <> 'array' then
    raise exception 'games must be an array' using errcode = '22023';
  end if;
  delete from xix.games x where x.round_id = set_games.round_id;
  for g in select * from jsonb_array_elements(set_games.games) loop
    gid := coalesce((g ->> 'id')::uuid, gen_random_uuid());
    insert into xix.games (id, round_id, format, options)
    values (gid, set_games.round_id, g ->> 'format', coalesce(g -> 'options', '{}'::jsonb));
    for pid in select jsonb_array_elements_text(coalesce(g -> 'players', '[]'::jsonb)) loop
      if not exists (select 1 from xix.players x where x.id = pid::uuid and x.round_id = set_games.round_id) then
        raise exception 'player % is not in this round', pid using errcode = '23503';
      end if;
      insert into xix.game_players (game_id, round_id, player_id, side)
      values (gid, set_games.round_id, pid::uuid, (g -> 'sides' ->> pid)::smallint);
    end loop;
  end loop;
  return query select * from xix.games x where x.round_id = set_games.round_id order by created_at;
end;
$$;

-- Upsert a score with last-write-wins on client_ts. Own row, or any row as owner.
create or replace function xix.enter_score(round_id uuid, player_id uuid, hole smallint, strokes smallint,
                                           picked_up boolean, client_ts timestamptz)
returns xix.scores language plpgsql security definer set search_path = xix, pg_temp as $$
#variable_conflict use_column
declare me uuid := (xix.ensure_profile()).id; r xix.rounds; s xix.scores;
begin
  select * into r from xix.rounds x where x.id = enter_score.round_id;
  if not found or not xix.is_round_member(enter_score.round_id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  if r.status = 'ended' then
    raise exception 'round has ended' using errcode = '55000';
  end if;
  if enter_score.hole < 1 or enter_score.hole > r.holes then
    raise exception 'hole % is not in this round', enter_score.hole using errcode = '22023';
  end if;
  if not (xix.is_round_owner(enter_score.round_id) or xix.is_own_player_row(enter_score.round_id, enter_score.player_id)) then
    raise exception 'you can enter scores for your own row only' using errcode = '42501';
  end if;
  if not enter_score.picked_up and enter_score.strokes is null then
    raise exception 'strokes required unless picked up' using errcode = '22023';
  end if;
  insert into xix.scores as sc (round_id, player_id, hole, strokes, picked_up, entered_by, client_ts)
  values (enter_score.round_id, enter_score.player_id, enter_score.hole,
          case when enter_score.picked_up then null else enter_score.strokes end, enter_score.picked_up, me, enter_score.client_ts)
  on conflict (round_id, player_id, hole) do update
    set strokes = excluded.strokes, picked_up = excluded.picked_up, entered_by = excluded.entered_by, client_ts = excluded.client_ts
    where coalesce(excluded.client_ts, now()) >= coalesce(sc.client_ts, '-infinity'::timestamptz);
  select * into s from xix.scores x
   where x.round_id = enter_score.round_id and x.player_id = enter_score.player_id and x.hole = enter_score.hole;
  return s;
end;
$$;

-- A member calls out one player or the crew on a hole nobody involved has scored yet.
create or replace function xix.create_callout(round_id uuid, hole smallint, kind text, target_ids uuid[], params jsonb)
returns xix.callouts language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; caller uuid; targets uuid[]; t uuid; c xix.callouts; r xix.rounds;
begin
  select * into r from xix.rounds x where x.id = create_callout.round_id;
  if not found or not xix.is_round_member(create_callout.round_id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  if r.status = 'ended' then
    raise exception 'round has ended' using errcode = '55000';
  end if;
  caller := xix.my_player_id(create_callout.round_id);
  if caller is null then
    raise exception 'you need a player row to call out' using errcode = '42501';
  end if;
  if hole < 1 or hole > r.holes then
    raise exception 'hole % is not in this round', hole using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct x), '{}') into targets from unnest(coalesce(target_ids, '{}')) as x where x <> caller;
  if cardinality(targets) = 0 then
    raise exception 'a callout needs at least one target other than the caller' using errcode = '22023';
  end if;
  foreach t in array targets loop
    if not exists (select 1 from xix.players x where x.id = t and x.round_id = create_callout.round_id and x.left_at is null) then
      raise exception 'target % is not in this round', t using errcode = '23503';
    end if;
  end loop;
  if kind = 'duel' and cardinality(targets) <> 1 then
    raise exception 'a duel has exactly one target' using errcode = '22023';
  end if;
  if kind = 'multiplier' and not exists (select 1 from xix.games g where g.round_id = create_callout.round_id and g.id = (params ->> 'game_id')::uuid) then
    raise exception 'multiplier needs a game in this round' using errcode = '22023';
  end if;
  if exists (select 1 from xix.scores s where s.round_id = create_callout.round_id and s.hole = create_callout.hole
             and (s.player_id = caller or s.player_id = any (targets))) then
    raise exception 'a participant has already scored hole %', hole using errcode = '55000';
  end if;
  insert into xix.callouts (round_id, hole, kind, caller_id, target_ids, params)
  values (create_callout.round_id, create_callout.hole, create_callout.kind, caller, targets, coalesce(create_callout.params, '{}'::jsonb))
  returning * into c;
  return c;
end;
$$;

-- A target signs or ducks, once, while the hole is open.
create or replace function xix.respond_callout(callout_id uuid, action text)
returns xix.callout_responses language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; c xix.callouts; mine uuid; resp xix.callout_responses;
begin
  select * into c from xix.callouts x where x.id = respond_callout.callout_id;
  if not found or not xix.is_round_member(c.round_id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  mine := xix.my_player_id(c.round_id);
  if mine is null or not (mine = any (c.target_ids)) then
    raise exception 'this callout was not sent to you' using errcode = '42501';
  end if;
  if c.closed_at is not null then
    raise exception 'the hole is closed to responses' using errcode = '55000';
  end if;
  if exists (select 1 from xix.callout_responses x where x.callout_id = c.id and x.player_id = mine) then
    raise exception 'you have already responded' using errcode = '23505';
  end if;
  insert into xix.callout_responses (callout_id, player_id, action)
  values (c.id, mine, respond_callout.action)
  returning * into resp;
  return resp;
end;
$$;

-- A member throws a sticker at another player's cell. Base pack only until packs arrive (Build Doc 3).
create or replace function xix.send_sticker(round_id uuid, hole smallint, target_player_id uuid, sticker_key text,
                                            pack_key text default 'base')
returns xix.stickers language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; sender uuid; st xix.stickers;
begin
  if not xix.is_round_member(send_sticker.round_id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  sender := xix.my_player_id(send_sticker.round_id);
  if sender is null then
    raise exception 'you need a player row to send stickers' using errcode = '42501';
  end if;
  if not exists (select 1 from xix.players x where x.id = send_sticker.target_player_id and x.round_id = send_sticker.round_id) then
    raise exception 'target is not in this round' using errcode = '23503';
  end if;
  if coalesce(pack_key, 'base') <> 'base' then
    raise exception 'pack % is not available' , pack_key using errcode = '42501';
  end if;
  if (select count(*) from xix.stickers x
       where x.round_id = send_sticker.round_id and x.hole = send_sticker.hole and x.sender_player_id = sender) >= 3 then
    raise exception 'three stickers per hole' using errcode = '23514';
  end if;
  insert into xix.stickers (round_id, hole, target_player_id, sender_player_id, sticker_key, pack_key)
  values (send_sticker.round_id, send_sticker.hole, send_sticker.target_player_id, sender, send_sticker.sticker_key,
          coalesce(send_sticker.pack_key, 'base'))
  returning * into st;
  return st;
end;
$$;

-- Ask for an authoritative engine run for a round (used by end_round and the triggers in 0011).
create or replace function xix.enqueue_engine_run(round_id uuid)
returns void language plpgsql security definer set search_path = xix, pg_temp as $$
#variable_conflict use_column
begin
  insert into xix.engine_queue (round_id) values (enqueue_engine_run.round_id)
  on conflict (round_id) do update set requested_at = now();
  perform pg_notify('xix_engine', enqueue_engine_run.round_id::text);
end;
$$;

create or replace function xix.end_round(round_id uuid)
returns xix.rounds language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; r xix.rounds;
begin
  if not xix.is_round_owner(end_round.round_id) then
    raise exception 'only the round owner can end it' using errcode = '42501';
  end if;
  update xix.rounds x set status = 'ended', ended_at = coalesce(x.ended_at, now())
   where x.id = end_round.round_id returning x.* into r;
  perform xix.enqueue_engine_run(end_round.round_id);
  return r;
end;
$$;

create or replace function xix.leave_round(round_id uuid)
returns xix.players language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; p xix.players;
begin
  update xix.players x set left_at = coalesce(x.left_at, now())
   where x.round_id = leave_round.round_id and x.profile_id = me
   returning x.* into p;
  if not found then
    raise exception 'you are not in this round' using errcode = '42501';
  end if;
  return p;
end;
$$;

create or replace function xix.confirm_round(round_id uuid, action text)
returns xix.confirmations language plpgsql security definer set search_path = xix, pg_temp as $$
#variable_conflict use_column
declare me uuid := (xix.ensure_profile()).id; c xix.confirmations;
begin
  if not exists (select 1 from xix.players x where x.round_id = confirm_round.round_id and x.profile_id = me)
     and not xix.is_round_owner(confirm_round.round_id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  insert into xix.confirmations (round_id, profile_id, action)
  values (confirm_round.round_id, me, confirm_round.action)
  on conflict (round_id, profile_id) do nothing;
  select * into c from xix.confirmations x where x.round_id = confirm_round.round_id and x.profile_id = me;
  return c;
end;
$$;

revoke execute on all functions in schema xix from public, anon;
-- The join-code default runs as the inserting user.
grant execute on function xix.gen_join_code() to authenticated;
grant execute on function
  xix.ensure_profile(), xix.join_round(text), xix.claim_row(uuid, uuid), xix.add_guest(uuid, text), xix.set_games(uuid, jsonb),
  xix.enter_score(uuid, uuid, smallint, smallint, boolean, timestamptz),
  xix.create_callout(uuid, smallint, text, uuid[], jsonb), xix.respond_callout(uuid, text),
  xix.send_sticker(uuid, smallint, uuid, text, text), xix.end_round(uuid), xix.leave_round(uuid),
  xix.confirm_round(uuid, text)
to authenticated;
