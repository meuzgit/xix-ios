-- 0004: games and game_players (Build Doc 2 A.2 #4). Formats mirror XIXScoring.Format raw values.

create table xix.games (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references xix.rounds (id) on delete cascade,
  format      text not null check (format in (
                'stroke_play', 'stableford', 'match_play', 'nassau', 'skins', 'best_ball',
                'scramble', 'shamble', 'alternate_shot', 'chapman', 'vegas', 'nines', 'sixes',
                'quota', 'rabbit', 'defender', 'fewest_blow_ups', 'beat_your_average',
                'bogey_golf', 'most_pars', 'first_to_five', 'worst_hole')),
  options     jsonb not null default '{}'::jsonb,   -- e.g. {"net": false, "carryover": true, "validation": false}
  created_at  timestamptz not null default now(),
  unique (id, round_id)
);

create table xix.game_players (
  game_id    uuid not null,
  round_id   uuid not null,
  player_id  uuid not null,
  side       smallint check (side between 0 and 3),  -- team formats: 0/1; individual: null
  primary key (game_id, player_id),
  foreign key (game_id, round_id) references xix.games (id, round_id) on delete cascade,
  foreign key (player_id, round_id) references xix.players (id, round_id) on delete cascade
);

grant select on xix.games to authenticated;
grant select on xix.game_players to authenticated;
