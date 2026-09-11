-- 0007: results cache, medals, confirmations, engine queue (Build Doc 2 A.2 #7, A.5, B.2)

-- Engine output cache; rebuildable at any time.
create table xix.results (
  round_id     uuid primary key references xix.rounds (id) on delete cascade,
  version      integer not null,                      -- engine version that produced it
  payload      jsonb not null,                        -- RoundResult (Build Doc 1 B.3)
  computed_at  timestamptz not null default now()
);

-- Append-only; a recompute never revokes a medal (Build Doc 1 B.10).
create table xix.medals (
  id                   uuid primary key default gen_random_uuid(),
  profile_id           uuid not null references xix.profiles (id) on delete cascade,
  round_id             uuid not null references xix.rounds (id) on delete cascade,
  key                  text not null,                 -- 'nassau_front', 'skins_two', 'callout_called_it', ...
  opponent_profile_id  uuid references xix.profiles (id) on delete set null,
  context              jsonb not null default '{}'::jsonb,   -- {"course": ..., "date": ..., "holes": [4, 9]}
  created_at           timestamptz not null default now(),
  unique (profile_id, round_id, key)
);

create table xix.confirmations (
  round_id    uuid not null references xix.rounds (id) on delete cascade,
  profile_id  uuid not null references xix.profiles (id) on delete cascade,
  action      text not null check (action in ('confirm', 'object')),
  created_at  timestamptz not null default now(),
  primary key (round_id, profile_id)
);

-- Rounds waiting for an authoritative engine run; one row per round.
create table xix.engine_queue (
  round_id      uuid primary key references xix.rounds (id) on delete cascade,
  requested_at  timestamptz not null default now(),
  attempts      integer not null default 0,
  last_error    text
);

-- Runs that failed five times.
create table xix.engine_dead_letter (
  id         uuid primary key default gen_random_uuid(),
  round_id   uuid not null references xix.rounds (id) on delete cascade,
  error      text,
  failed_at  timestamptz not null default now()
);

grant select on xix.results to authenticated;
grant select on xix.medals to authenticated;
grant select, insert on xix.confirmations to authenticated;
