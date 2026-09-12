-- 0016: joinable_rows now answers the whole join screen in one call (Build Doc 2 C.4, review of step 3):
-- the round (course, date, holes, status) and every player row with a claimable flag. Non-members may
-- call it for an open round's code; nothing else about the round is exposed.

drop function if exists xix.joinable_rows(text);

create or replace function xix.joinable_rows(code text)
returns jsonb language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare r xix.rounds; out jsonb;
begin
  perform xix.require_auth();
  select * into r from xix.rounds x where x.join_code = upper(trim(joinable_rows.code)) and x.status in ('setup', 'live');
  if not found then
    raise exception 'no open round for that code' using errcode = 'P0002';
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

revoke execute on function xix.joinable_rows(text) from public, anon;
grant execute on function xix.joinable_rows(text) to authenticated;
