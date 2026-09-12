-- 0019: a join code keeps answering after the round has ended (Build Doc 3 step 1, result-link confirm).
-- A guest who was scored by name opens the result link after the round, signs in, and claims their row
-- (claim_row already allows 'ended'); join_round and joinable_rows must resolve the code for that.
-- Membership rules are unchanged: neither call exposes anything beyond the join screen.

create or replace function xix.join_round(code text)
returns xix.rounds language plpgsql security definer set search_path = xix, pg_temp as $$
declare r xix.rounds;
begin
  perform xix.ensure_profile();
  select * into r from xix.rounds where join_code = upper(trim(join_round.code)) and status in ('setup', 'live', 'ended');
  if not found then
    raise exception 'no round for that code' using errcode = 'P0002';
  end if;
  return r;
end;
$$;

create or replace function xix.joinable_rows(code text)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare r xix.rounds; out jsonb;
begin
  perform xix.require_auth();
  select * into r from xix.rounds x where x.join_code = upper(trim(joinable_rows.code)) and x.status in ('setup', 'live', 'ended');
  if not found then
    raise exception 'no round for that code' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'round', jsonb_build_object(
      'id', r.id, 'join_code', r.join_code, 'holes', r.holes, 'status', r.status, 'played_on', r.played_on,
      'course', (select c.name from xix.courses c where c.id = r.course_id),
      'owner', (select p.display_name from xix.players p where p.round_id = r.id and p.profile_id = r.owner_id limit 1)),
    'players', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'display_name', p.display_name, 'seat', p.seat, 'claimable', p.profile_id is null and p.left_at is null,
      'mine', coalesce(p.profile_id = auth.uid(), false)) order by p.seat), '[]'::jsonb)
      from xix.players p where p.round_id = r.id)
  ) into out;
  return out;
end;
$$;

revoke execute on function xix.join_round(text), xix.joinable_rows(text) from public, anon;
grant execute on function xix.join_round(text), xix.joinable_rows(text) to authenticated;
