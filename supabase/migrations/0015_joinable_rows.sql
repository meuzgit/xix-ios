-- 0015: the join-by-link flow needs the claimable rows before the caller is a member (Build Doc 2 C.4).
-- join_round returns the round; this returns its unclaimed rows for the same code, nothing else.

create or replace function xix.joinable_rows(code text)
returns table (id uuid, display_name text, seat smallint)
language plpgsql stable security definer set search_path = xix, pg_temp as $$
declare r xix.rounds;
begin
  perform xix.require_auth();
  select * into r from xix.rounds x where x.join_code = upper(trim(joinable_rows.code)) and x.status in ('setup', 'live');
  if not found then
    raise exception 'no open round for that code' using errcode = 'P0002';
  end if;
  return query select p.id, p.display_name, p.seat from xix.players p
    where p.round_id = r.id and p.profile_id is null order by p.seat;
end;
$$;

revoke execute on function xix.joinable_rows(text) from public, anon;
grant execute on function xix.joinable_rows(text) to authenticated;
