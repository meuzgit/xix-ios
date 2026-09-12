-- 0017: games keep their setup order. Rows written in one set_games call share a created_at, so the
-- engine input (and with it pill order and medal order) needs an explicit position.

alter table xix.games add column position smallint not null default 0;

create or replace function xix.set_games(round_id uuid, games jsonb)
returns setof xix.games language plpgsql security definer set search_path = xix, pg_temp as $$
declare me uuid := (xix.ensure_profile()).id; g jsonb; gid uuid; pid text; pos int := 0;
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
    insert into xix.games (id, round_id, format, options, position)
    values (gid, set_games.round_id, g ->> 'format', coalesce(g -> 'options', '{}'::jsonb), pos);
    pos := pos + 1;
    for pid in select jsonb_array_elements_text(coalesce(g -> 'players', '[]'::jsonb)) loop
      if not exists (select 1 from xix.players x where x.id = pid::uuid and x.round_id = set_games.round_id) then
        raise exception 'player % is not in this round', pid using errcode = '23503';
      end if;
      insert into xix.game_players (game_id, round_id, player_id, side)
      values (gid, set_games.round_id, pid::uuid, (g -> 'sides' ->> pid)::smallint);
    end loop;
  end loop;
  return query select * from xix.games x where x.round_id = set_games.round_id order by x.position, x.created_at, x.id;
end;
$$;

-- round_input: games in setup order.
create or replace function xix.round_input(round_id uuid)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare r xix.rounds; out jsonb;
begin
  select * into r from xix.rounds x where x.id = round_input.round_id;
  if not found then
    raise exception 'round not found' using errcode = 'P0002';
  end if;
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
                  order by g.position, g.created_at, g.id), '[]'::jsonb)
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
