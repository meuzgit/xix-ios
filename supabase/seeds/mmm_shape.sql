-- A stand-in for MMM's shape, on the local stack only, so Where to now can be built and tested before
-- MMM's schema owner confirms the real columns (docs/mmm-where-to-now-proposal.md). This is not MMM's
-- data and not MMM's schema: it is the smallest thing shaped like the assumptions in the proposal.
--
-- It runs from [db.seed] sql_paths, which only `supabase db reset` reads, and `db reset` is local only.
-- Nothing here is ever pushed: no migration creates any of it.

create schema if not exists mmm;

create table if not exists mmm.places (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  city               text not null,
  category           text not null check (category in ('eat', 'drink', 'stay', 'do')),
  illustration_path  text,
  lat                double precision not null,
  lng                double precision not null,
  drive_minutes      integer,
  is_open            boolean not null default true,
  status_line        text,
  rank               integer,
  is_visible         boolean not null default true
);

create table if not exists mmm.likes (
  profile_id uuid not null,
  place_id   uuid not null references mmm.places(id) on delete cascade,
  primary key (profile_id, place_id)
);

create table if not exists mmm.bookmarks (
  profile_id uuid not null,
  place_id   uuid not null references mmm.places(id) on delete cascade,
  primary key (profile_id, place_id)
);

create table if not exists mmm.follows (
  profile_id          uuid not null,
  followed_profile_id uuid not null,
  primary key (profile_id, followed_profile_id)
);

create table if not exists mmm.subscriptions (
  profile_id          uuid primary key,
  status              text not null,
  current_period_end  timestamptz
);

create table if not exists mmm.place_views (
  profile_id uuid not null,
  place_id   uuid not null references mmm.places(id) on delete cascade,
  viewed_at  timestamptz not null default now()
);

-- MMM's free-allowance rule, stubbed. The real numbers come from MMM; the copy on the locked card has
-- to mirror them, so XIX reads them rather than hard-coding any.
create or replace function mmm.free_allowance_per_period() returns integer language sql immutable as $$ select 3 $$;
create or replace function mmm.free_allowance_period() returns text language sql immutable as $$ select 'week' $$;

-- Five places around Fraserview, two of them liked by somebody Ray follows.
insert into mmm.places (id, name, city, category, illustration_path, lat, lng, drive_minutes, is_open, status_line, rank)
values
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1', 'Kinsman', 'Vancouver', 'drink', 'watercolor-kinsman-drink.png', 49.2185, -123.0720, 6, true, 'Open until 11', 1),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2', 'Katsu House', 'Vancouver', 'eat', 'watercolor-katsu-sando.png', 49.2256, -123.0811, 9, true, 'Kitchen closes at 9', 2),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3', 'Espresso Bar', 'Vancouver', 'drink', 'watercolor-espresso.png', 49.2301, -123.0602, 11, false, 'Opens at 7 tomorrow', 3),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4', 'Donut Shop', 'Burnaby', 'eat', 'watercolor-donut.png', 49.2488, -123.0021, 17, true, 'Open until 6', 4),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd5', 'Coffee and Cake', 'Vancouver', 'eat', 'watercolor-coffee-cake.png', 49.2110, -123.1040, 8, true, 'Open until 5', 5)
on conflict (id) do nothing;

-- Ray follows Dave; Dave likes two of them, so they are "from your circle".
insert into mmm.follows (profile_id, followed_profile_id)
values ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222')
on conflict do nothing;
insert into mmm.likes (profile_id, place_id)
values ('22222222-2222-4222-8222-222222222222', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2'),
       ('22222222-2222-4222-8222-222222222222', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1')
on conflict do nothing;

-- Dave is an Insider; Ray is not, and has spent one of his three this week.
insert into mmm.subscriptions (profile_id, status, current_period_end)
values ('22222222-2222-4222-8222-222222222222', 'active', now() + interval '30 days')
on conflict (profile_id) do nothing;
insert into mmm.place_views (profile_id, place_id, viewed_at)
values ('11111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-ddddddddddd5', now())
on conflict do nothing;

grant usage on schema mmm to postgres, service_role;
