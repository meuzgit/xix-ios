-- 0012: indexes (Build Doc 2 A.6). rounds(join_code) is covered by its unique constraint;
-- engine_queue(round_id) by its primary key; players(round_id, profile_id) by the partial unique index in 0002.

create index scores_round_hole on xix.scores (round_id, hole);
create index players_round_profile on xix.players (round_id, profile_id);
create index players_profile on xix.players (profile_id);
create index callouts_round_hole on xix.callouts (round_id, hole);
create index stickers_round_hole on xix.stickers (round_id, hole);
create index medals_profile_recent on xix.medals (profile_id, created_at desc);
create index game_players_round on xix.game_players (round_id);
create index callout_responses_player on xix.callout_responses (player_id);
