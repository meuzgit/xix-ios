-- 0008: crews (private boards) and materialised rankings (Build Doc 2 A.2 #8)

create table xix.crews (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  owner_id    uuid not null references xix.profiles (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table xix.crew_members (
  crew_id     uuid not null references xix.crews (id) on delete cascade,
  profile_id  uuid not null references xix.profiles (id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (crew_id, profile_id)
);

-- Materialised nightly by the ranking job (Build Doc 3).
create table xix.ranking_entries (
  profile_id   uuid not null references xix.profiles (id) on delete cascade,
  metric       text not null,                          -- 'stableford_vs_level', 'birdies', 'rounds', 'rival_points'
  "window"     text not null,                          -- 'month', 'all'
  value        numeric not null,
  computed_at  timestamptz not null default now(),
  primary key (profile_id, metric, "window")
);

grant select, insert, update, delete on xix.crews to authenticated;
grant select, insert, update, delete on xix.crew_members to authenticated;
grant select on xix.ranking_entries to authenticated;
