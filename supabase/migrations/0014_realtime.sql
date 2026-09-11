-- 0014: Realtime for the round channel (Build Doc 2 C.2). Postgres changes are only broadcast for
-- tables in the supabase_realtime publication; RLS still decides who receives each row. Full replica
-- identity so update and delete payloads carry round_id for the channel filters.

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;

alter publication supabase_realtime add table
  xix.rounds, xix.players, xix.scores, xix.games, xix.game_players,
  xix.callouts, xix.callout_responses, xix.stickers, xix.results;

alter table xix.rounds replica identity full;
alter table xix.players replica identity full;
alter table xix.scores replica identity full;
alter table xix.games replica identity full;
alter table xix.game_players replica identity full;
alter table xix.callouts replica identity full;
alter table xix.callout_responses replica identity full;
alter table xix.stickers replica identity full;
alter table xix.results replica identity full;
