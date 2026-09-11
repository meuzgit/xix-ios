-- 0003: scores (Build Doc 2 A.2 #3). updated_at is maintained by trigger (0011).

create table xix.scores (
  round_id    uuid not null references xix.rounds (id) on delete cascade,
  player_id   uuid not null,
  hole        smallint not null check (hole between 1 and 18),
  strokes     smallint check (strokes >= 1),          -- null = not entered; ignored when picked_up
  picked_up   boolean not null default false,         -- engine applies 2 × par (10 without par)
  entered_by  uuid references xix.profiles (id) on delete set null,
  client_ts   timestamptz,                            -- client monotonic timestamp; last-write-wins key for enter_score
  updated_at  timestamptz not null default now(),     -- server last-write-wins key
  primary key (round_id, player_id, hole),
  foreign key (player_id, round_id) references xix.players (id, round_id) on delete cascade,
  check (picked_up or strokes is not null)
);

grant select, insert, update on xix.scores to authenticated;
