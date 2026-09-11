-- 0002: rounds and players (Build Doc 2 A.2 #2)

-- Six characters from an unambiguous alphabet (no I, O, 0, 1), unique among rounds.
create or replace function xix.gen_join_code()
returns text
language plpgsql
volatile
set search_path = xix, pg_temp
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
  i int;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from xix.rounds where join_code = code);
  end loop;
  return code;
end;
$$;

create table xix.rounds (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references xix.profiles (id) on delete cascade,
  course_id   uuid references xix.courses (id) on delete set null,
  played_on   date not null default current_date,
  holes       smallint not null default 18 check (holes in (9, 18)),
  status      text not null default 'setup' check (status in ('setup', 'live', 'ended')),
  join_code   text not null unique,                  -- xix.golf/r/{code}
  ended_at    timestamptz,
  counted_at  timestamptz,                           -- set by auto_confirm or once confirmed
  created_at  timestamptz not null default now()
);

-- Default the join code after the table exists (the generator reads it).
alter table xix.rounds alter column join_code set default xix.gen_join_code();

-- players: one row per person in the round; unclaimed rows belong to the round owner.
create table xix.players (
  id              uuid primary key default gen_random_uuid(),
  round_id        uuid not null references xix.rounds (id) on delete cascade,
  profile_id      uuid references xix.profiles (id) on delete set null,   -- null until claimed
  display_name    text not null,
  seat            smallint not null check (seat between 0 and 3),
  level_snapshot  numeric(4,1),                                          -- Level at round start, for net games
  claimed_at      timestamptz,
  left_at         timestamptz,
  created_at      timestamptz not null default now(),
  unique (round_id, seat),
  unique (id, round_id)                              -- lets child tables pin a player to its round
);

create unique index players_one_row_per_profile on xix.players (round_id, profile_id) where profile_id is not null;

grant select, insert, update, delete on xix.rounds to authenticated;
grant select, insert, update, delete on xix.players to authenticated;
