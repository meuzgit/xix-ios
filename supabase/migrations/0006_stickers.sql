-- 0006: stickers (Build Doc 2 A.2 #6). Stickers are speech: every sticker has a sender.

create table xix.stickers (
  id                uuid primary key default gen_random_uuid(),
  round_id          uuid not null references xix.rounds (id) on delete cascade,
  hole              smallint not null check (hole between 1 and 18),
  target_player_id  uuid not null,
  sender_player_id  uuid not null,
  sticker_key       text not null,                    -- 'YIKES', 'CLUTCH', ...
  pack_key          text not null default 'base',
  played_at         timestamptz,                      -- recipient tapped it
  created_at        timestamptz not null default now(),
  foreign key (target_player_id, round_id) references xix.players (id, round_id) on delete cascade,
  foreign key (sender_player_id, round_id) references xix.players (id, round_id) on delete cascade
);

grant select, update on xix.stickers to authenticated;
