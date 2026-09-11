-- 0009: row-level security (Build Doc 2 A.3). Helpers run as owner to avoid recursive policy checks.

create or replace function xix.is_round_owner(p_round uuid)
returns boolean language sql stable security definer set search_path = xix, pg_temp as $$
  select exists (select 1 from xix.rounds r where r.id = p_round and r.owner_id = auth.uid());
$$;

-- A member is the owner, or a player with a claimed row who has not left.
create or replace function xix.is_round_member(p_round uuid)
returns boolean language sql stable security definer set search_path = xix, pg_temp as $$
  select xix.is_round_owner(p_round)
      or exists (select 1 from xix.players p
                 where p.round_id = p_round and p.profile_id = auth.uid() and p.left_at is null);
$$;

create or replace function xix.my_player_id(p_round uuid)
returns uuid language sql stable security definer set search_path = xix, pg_temp as $$
  select p.id from xix.players p where p.round_id = p_round and p.profile_id = auth.uid() limit 1;
$$;

-- Another profile that shares a round (both have player rows) or a crew with the caller.
create or replace function xix.shares_round_or_crew(p_profile uuid)
returns boolean language sql stable security definer set search_path = xix, pg_temp as $$
  select p_profile = auth.uid()
      or exists (select 1 from xix.players a join xix.players b on a.round_id = b.round_id
                 where a.profile_id = auth.uid() and b.profile_id = p_profile)
      or exists (select 1 from xix.rounds r join xix.players b on b.round_id = r.id
                 where r.owner_id = auth.uid() and b.profile_id = p_profile)
      or exists (select 1 from xix.rounds r join xix.players a on a.round_id = r.id
                 where r.owner_id = p_profile and a.profile_id = auth.uid())
      or exists (select 1 from xix.crew_members a join xix.crew_members b on a.crew_id = b.crew_id
                 where a.profile_id = auth.uid() and b.profile_id = p_profile)
      or exists (select 1 from xix.crews c join xix.crew_members m on m.crew_id = c.id
                 where (c.owner_id = auth.uid() and m.profile_id = p_profile)
                    or (c.owner_id = p_profile and m.profile_id = auth.uid()));
$$;

grant execute on function xix.is_round_owner(uuid), xix.is_round_member(uuid), xix.my_player_id(uuid),
  xix.shares_round_or_crew(uuid) to authenticated;

-- Names of people you share a round or crew with; the profiles table itself is own-row only.
create view xix.public_profiles as
  select id, display_name from xix.profiles where xix.shares_round_or_crew(id);
grant select on xix.public_profiles to authenticated;

alter table xix.profiles enable row level security;
alter table xix.courses enable row level security;
alter table xix.course_holes enable row level security;
alter table xix.rounds enable row level security;
alter table xix.players enable row level security;
alter table xix.scores enable row level security;
alter table xix.games enable row level security;
alter table xix.game_players enable row level security;
alter table xix.callouts enable row level security;
alter table xix.callout_responses enable row level security;
alter table xix.stickers enable row level security;
alter table xix.results enable row level security;
alter table xix.medals enable row level security;
alter table xix.confirmations enable row level security;
alter table xix.engine_queue enable row level security;
alter table xix.engine_dead_letter enable row level security;
alter table xix.crews enable row level security;
alter table xix.crew_members enable row level security;
alter table xix.ranking_entries enable row level security;

-- profiles: own row; insert only through ensure_profile(); no delete.
create policy profiles_select_own on xix.profiles for select to authenticated using (id = auth.uid());
create policy profiles_update_own on xix.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- courses / course_holes: any authenticated user reads and creates; the creator updates.
create policy courses_select on xix.courses for select to authenticated using (true);
create policy courses_insert on xix.courses for insert to authenticated with check (created_by = auth.uid());
create policy courses_update_creator on xix.courses for update to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy course_holes_select on xix.course_holes for select to authenticated using (true);
create policy course_holes_insert on xix.course_holes for insert to authenticated
  with check (exists (select 1 from xix.courses c where c.id = course_id and c.created_by = auth.uid()));
create policy course_holes_update_creator on xix.course_holes for update to authenticated
  using (exists (select 1 from xix.courses c where c.id = course_id and c.created_by = auth.uid()));

-- rounds: members read; join by code goes through the join_round RPC.
-- owner_id is checked directly so "insert … returning" sees the new row (the helper runs on the statement's snapshot).
create policy rounds_select_member on xix.rounds for select to authenticated
  using (owner_id = auth.uid() or xix.is_round_member(id));
create policy rounds_insert_owner on xix.rounds for insert to authenticated with check (owner_id = auth.uid());
create policy rounds_update_owner on xix.rounds for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy rounds_delete_owner_setup on xix.rounds for delete to authenticated
  using (owner_id = auth.uid() and status = 'setup');

-- players: members read; owner writes any row; a member may update their own row (display_name only, see guard).
create policy players_select_member on xix.players for select to authenticated using (xix.is_round_member(round_id));
create policy players_insert_owner on xix.players for insert to authenticated with check (xix.is_round_owner(round_id));
create policy players_update_owner_or_own on xix.players for update to authenticated
  using (xix.is_round_owner(round_id) or profile_id = auth.uid())
  with check (xix.is_round_owner(round_id) or profile_id = auth.uid());
create policy players_delete_owner_unclaimed on xix.players for delete to authenticated
  using (xix.is_round_owner(round_id) and claimed_at is null);

create or replace function xix.players_member_update_guard()
returns trigger language plpgsql security definer set search_path = xix, pg_temp as $$
begin
  if xix.is_round_owner(new.round_id) then
    return new;
  end if;
  -- Claiming a free row as yourself (claim_row) and leaving (leave_round) are the two changes a
  -- non-owner may make beyond display_name; both go through their RPCs.
  if old.profile_id is null and new.profile_id = auth.uid() and new.claimed_at is not null
     and new.round_id = old.round_id and new.seat = old.seat and new.level_snapshot is not distinct from old.level_snapshot
     and new.left_at is not distinct from old.left_at then
    return new;
  end if;
  if new.round_id is distinct from old.round_id or new.profile_id is distinct from old.profile_id
     or new.seat is distinct from old.seat or new.level_snapshot is distinct from old.level_snapshot
     or new.claimed_at is distinct from old.claimed_at then
    raise exception 'members may change only their own display_name' using errcode = '42501';
  end if;
  if new.left_at is distinct from old.left_at and old.profile_id is distinct from auth.uid() then
    raise exception 'only the player or the owner can mark a row as left' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger players_member_update_guard before update on xix.players
  for each row execute function xix.players_member_update_guard();

-- scores: members read; own row or owner writes.
create or replace function xix.is_own_player_row(p_round uuid, p_player uuid)
returns boolean language sql stable security definer set search_path = xix, pg_temp as $$
  select exists (select 1 from xix.players p where p.id = p_player and p.round_id = p_round and p.profile_id = auth.uid());
$$;
grant execute on function xix.is_own_player_row(uuid, uuid) to authenticated;

create policy scores_select_member on xix.scores for select to authenticated using (xix.is_round_member(round_id));
create policy scores_insert_own_or_owner on xix.scores for insert to authenticated
  with check (xix.is_round_owner(round_id) or xix.is_own_player_row(round_id, player_id));
create policy scores_update_own_or_owner on xix.scores for update to authenticated
  using (xix.is_round_owner(round_id) or xix.is_own_player_row(round_id, player_id))
  with check (xix.is_round_owner(round_id) or xix.is_own_player_row(round_id, player_id));

-- games / game_players: members read; writes only through set_games.
create policy games_select_member on xix.games for select to authenticated using (xix.is_round_member(round_id));
create policy game_players_select_member on xix.game_players for select to authenticated using (xix.is_round_member(round_id));

-- callouts / responses: members read; writes only through create_callout and respond_callout.
create policy callouts_select_member on xix.callouts for select to authenticated using (xix.is_round_member(round_id));
create policy callout_responses_select_member on xix.callout_responses for select to authenticated
  using (exists (select 1 from xix.callouts c where c.id = callout_id and xix.is_round_member(c.round_id)));

-- stickers: members read; insert only through send_sticker; the target marks played_at (guard below).
create policy stickers_select_member on xix.stickers for select to authenticated using (xix.is_round_member(round_id));
create policy stickers_update_target on xix.stickers for update to authenticated
  using (xix.is_own_player_row(round_id, target_player_id))
  with check (xix.is_own_player_row(round_id, target_player_id));

create or replace function xix.stickers_target_update_guard()
returns trigger language plpgsql as $$
begin
  if new.round_id is distinct from old.round_id or new.hole is distinct from old.hole
     or new.target_player_id is distinct from old.target_player_id or new.sender_player_id is distinct from old.sender_player_id
     or new.sticker_key is distinct from old.sticker_key or new.pack_key is distinct from old.pack_key then
    raise exception 'only played_at may change on a sticker' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger stickers_target_update_guard before update on xix.stickers
  for each row execute function xix.stickers_target_update_guard();

-- results / medals / confirmations: engine writes results and medals (service role bypasses RLS).
create policy results_select_member on xix.results for select to authenticated using (xix.is_round_member(round_id));
create policy medals_select_own on xix.medals for select to authenticated using (profile_id = auth.uid());
create policy confirmations_select_member on xix.confirmations for select to authenticated using (xix.is_round_member(round_id));
create policy confirmations_insert_own on xix.confirmations for insert to authenticated
  with check (profile_id = auth.uid() and xix.is_round_member(round_id));

-- crews: members and the owner read; anyone creates a crew they own; the owner manages it.
create or replace function xix.is_crew_member(p_crew uuid)
returns boolean language sql stable security definer set search_path = xix, pg_temp as $$
  select exists (select 1 from xix.crews c where c.id = p_crew and c.owner_id = auth.uid())
      or exists (select 1 from xix.crew_members m where m.crew_id = p_crew and m.profile_id = auth.uid());
$$;
create or replace function xix.is_crew_owner(p_crew uuid)
returns boolean language sql stable security definer set search_path = xix, pg_temp as $$
  select exists (select 1 from xix.crews c where c.id = p_crew and c.owner_id = auth.uid());
$$;
grant execute on function xix.is_crew_member(uuid), xix.is_crew_owner(uuid) to authenticated;

create policy crews_select_member on xix.crews for select to authenticated
  using (owner_id = auth.uid() or xix.is_crew_member(id));
create policy crews_insert_owner on xix.crews for insert to authenticated with check (owner_id = auth.uid());
create policy crews_update_owner on xix.crews for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy crews_delete_owner on xix.crews for delete to authenticated using (owner_id = auth.uid());
create policy crew_members_select_member on xix.crew_members for select to authenticated using (xix.is_crew_member(crew_id));
create policy crew_members_insert_owner on xix.crew_members for insert to authenticated with check (xix.is_crew_owner(crew_id));
create policy crew_members_update_owner on xix.crew_members for update to authenticated using (xix.is_crew_owner(crew_id));
create policy crew_members_delete_owner on xix.crew_members for delete to authenticated using (xix.is_crew_owner(crew_id));

-- ranking_entries: everyone signed in reads; the ranking job writes.
create policy ranking_entries_select on xix.ranking_entries for select to authenticated using (true);
