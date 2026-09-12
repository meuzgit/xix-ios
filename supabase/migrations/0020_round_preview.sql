-- 0020: the no-app landing page (Build Doc 3 step 1 follow-up, Pass 6 §2). An anonymous-readable,
-- SECURITY DEFINER read of one round by join code, returning only what the page prints: course name,
-- region, played_on, holes, status, the owner's display name and the players' display names. No ids,
-- no scores, no games. One row, cheap; an unknown code answers null rather than an error so the page
-- (and anyone hammering it) gets nothing to work with. The only xix function anon may call.

create or replace function xix.round_preview(code text)
returns jsonb language sql stable security definer set search_path = xix, pg_temp as $$
  select jsonb_build_object(
    'course', c.name,
    'region', c.region,
    'played_on', r.played_on,
    'holes', r.holes,
    'status', r.status,
    'owner', (select p.display_name from xix.players p where p.round_id = r.id and p.profile_id = r.owner_id limit 1),
    'players', (select coalesce(jsonb_agg(p.display_name order by p.seat), '[]'::jsonb) from xix.players p where p.round_id = r.id and p.left_at is null))
  from xix.rounds r
  left join xix.courses c on c.id = r.course_id
  where r.join_code = upper(trim(round_preview.code))
  limit 1;
$$;

revoke execute on function xix.round_preview(text) from public;
grant execute on function xix.round_preview(text) to anon, authenticated;
