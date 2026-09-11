-- 0013: engine runtime support (Build Doc 2 B.2). The xix-engine edge function reads a round as the
-- engine's RoundInput, runs XIXScoring, and hands the RoundResult back to apply_engine_result.

-- RoundInput in the fixture shape: player ids are player row uuids, names are display names,
-- scores keyed by player id with "PU" for a pick-up, games with options/players/sides, callouts with
-- per-target responses. A player who left is given extras.leftAfterHole = their last scored hole.
create or replace function xix.round_input(round_id uuid)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare r xix.rounds; out jsonb;
begin
  select * into r from xix.rounds x where x.id = round_input.round_id;
  if not found then
    raise exception 'round not found' using errcode = 'P0002';
  end if;
  -- Inside a security-definer function current_user is the owner, so only the JWT role can be trusted.
  if auth.role() is distinct from 'service_role' and not xix.is_round_member(r.id) then
    raise exception 'not a member of this round' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'holes', r.holes,
    'par', (select coalesce(jsonb_agg(ch.par order by h.n), '[]'::jsonb)
              from generate_series(1, r.holes) h(n)
              left join xix.course_holes ch on ch.course_id = r.course_id and ch.hole = h.n),
    'strokeIndex', (select coalesce(jsonb_agg(ch.stroke_index order by h.n), '[]'::jsonb)
              from generate_series(1, r.holes) h(n)
              left join xix.course_holes ch on ch.course_id = r.course_id and ch.hole = h.n),
    'players', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', p.id, 'name', p.display_name, 'level', p.level_snapshot,
                  'extras', case when p.left_at is not null
                                 then jsonb_build_object('leftAfterHole', coalesce((select max(s.hole) from xix.scores s where s.player_id = p.id), 0))
                                 else null end) order by p.seat), '[]'::jsonb)
                from xix.players p where p.round_id = r.id),
    'scores', (select coalesce(jsonb_object_agg(p.id, (
                  select coalesce(jsonb_agg(case when s.picked_up then to_jsonb('PU'::text) else to_jsonb(s.strokes) end order by h.n), '[]'::jsonb)
                    from generate_series(1, r.holes) h(n)
                    left join xix.scores s on s.round_id = r.id and s.player_id = p.id and s.hole = h.n)), '{}'::jsonb)
                from xix.players p where p.round_id = r.id),
    'games', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', g.id, 'format', g.format, 'options', g.options,
                  'players', (select coalesce(jsonb_agg(gp.player_id order by pl.seat), '[]'::jsonb)
                                from xix.game_players gp join xix.players pl on pl.id = gp.player_id where gp.game_id = g.id),
                  'sides', (select jsonb_object_agg(gp.player_id, gp.side) from xix.game_players gp where gp.game_id = g.id and gp.side is not null))
                  order by g.created_at, g.id), '[]'::jsonb)
                from xix.games g where g.round_id = r.id),
    'callouts', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', c.id, 'hole', c.hole, 'kind', c.kind, 'caller', c.caller_id, 'targets', to_jsonb(c.target_ids), 'params', c.params,
                  'responses', (select coalesce(jsonb_object_agg(cr.player_id, cr.action), '{}'::jsonb) from xix.callout_responses cr where cr.callout_id = c.id))
                  order by c.created_at, c.id), '[]'::jsonb)
                from xix.callouts c where c.round_id = r.id)
  ) into out;
  return out;
end;
$$;

-- Level from a rolling average vs par: the inverse of the engine's strokes formula in Build Doc 1 B.4
-- (strokes = (10 − level) × 2.4), so level = 10 − avgOverPar / 2.4, clamped to 1–10, one decimal.
-- Needs three complete rounds with par (PRD 8.8); returns null until then.
create or replace function xix.level_from_average(avg_over_par numeric, rounds_counted integer)
returns numeric language sql immutable as $$
  select case when rounds_counted < 3 or avg_over_par is null then null
              else least(10, greatest(1, round(10 - avg_over_par / 2.4, 1))) end;
$$;

-- Recompute level_auto for one profile over their last 10 complete rounds with par.
create or replace function xix.update_level_auto(profile_id uuid)
returns numeric language plpgsql security definer set search_path = xix, pg_temp as $$
declare avg_over numeric; n integer; lvl numeric;
begin
  with recent as (
    select (res.payload -> 'perPlayer' -> p.id::text ->> 'toPar')::numeric as to_par
      from xix.players p
      join xix.rounds r on r.id = p.round_id
      join xix.results res on res.round_id = r.id
     where p.profile_id = update_level_auto.profile_id
       and r.status = 'ended'
       and res.payload ->> 'status' = 'complete'
       and (res.payload -> 'perPlayer' -> p.id::text ->> 'toPar') is not null
     order by r.played_on desc, r.ended_at desc
     limit 10)
  select avg(to_par), count(*) into avg_over, n from recent;
  lvl := xix.level_from_average(avg_over, n);
  update xix.profiles x set level_auto = lvl where x.id = update_level_auto.profile_id;
  return lvl;
end;
$$;

-- Store an engine run. On a complete result for an ended round, award medals to claimed players
-- (idempotent by profile, round, key; never revoked) and refresh their Level. Consumes the queue row.
create or replace function xix.apply_engine_result(round_id uuid, version integer, payload jsonb)
returns void language plpgsql security definer set search_path = xix, pg_temp as $$
#variable_conflict use_column
declare r xix.rounds; m jsonb; course_name text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'engine results are written by the service role' using errcode = '42501';
  end if;
  select * into r from xix.rounds x where x.id = apply_engine_result.round_id;
  if not found then
    raise exception 'round not found' using errcode = 'P0002';
  end if;

  insert into xix.results (round_id, version, payload, computed_at)
  values (apply_engine_result.round_id, apply_engine_result.version, apply_engine_result.payload, now())
  on conflict (round_id) do update set version = excluded.version, payload = excluded.payload, computed_at = now();

  if apply_engine_result.payload ->> 'status' = 'complete' and r.status = 'ended' then
    select c.name into course_name from xix.courses c where c.id = r.course_id;
    for m in select * from jsonb_array_elements(coalesce(apply_engine_result.payload -> 'medals', '[]'::jsonb)) loop
      insert into xix.medals (profile_id, round_id, key, opponent_profile_id, context)
      select p.profile_id, r.id, m ->> 'key', o.profile_id,
             jsonb_strip_nulls(jsonb_build_object('course', course_name, 'date', r.played_on, 'holes', m -> 'holes'))
        from xix.players p
        left join xix.players o on o.id = nullif(m ->> 'opponent', '')::uuid
       where p.id = (m ->> 'profile')::uuid and p.profile_id is not null
      on conflict (profile_id, round_id, key) do nothing;
    end loop;
    perform xix.update_level_auto(p.profile_id) from xix.players p where p.round_id = r.id and p.profile_id is not null;
  end if;

  delete from xix.engine_queue q where q.round_id = apply_engine_result.round_id;
end;
$$;

-- A failed run stays queued for retry; after five failures it moves to the dead-letter table.
create or replace function xix.engine_run_failed(round_id uuid, error text)
returns void language plpgsql security definer set search_path = xix, pg_temp as $$
#variable_conflict use_column
declare attempts_now integer;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'engine failures are recorded by the service role' using errcode = '42501';
  end if;
  update xix.engine_queue q set attempts = q.attempts + 1, last_error = engine_run_failed.error
   where q.round_id = engine_run_failed.round_id
   returning q.attempts into attempts_now;
  if attempts_now >= 5 then
    insert into xix.engine_dead_letter (round_id, error) values (engine_run_failed.round_id, engine_run_failed.error);
    delete from xix.engine_queue q where q.round_id = engine_run_failed.round_id;
  end if;
end;
$$;

revoke execute on function xix.round_input(uuid), xix.apply_engine_result(uuid, integer, jsonb),
  xix.engine_run_failed(uuid, text), xix.update_level_auto(uuid), xix.level_from_average(numeric, integer) from public, anon, authenticated;
grant execute on function xix.round_input(uuid) to authenticated, service_role;
grant execute on function xix.apply_engine_result(uuid, integer, jsonb), xix.engine_run_failed(uuid, text),
  xix.update_level_auto(uuid) to service_role;
