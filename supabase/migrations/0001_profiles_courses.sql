-- 0001: schema, profiles, courses, course_holes (Build Doc 1 v1.2 A.2; Build Doc 2 A.2 #1)

create schema if not exists xix;

grant usage on schema xix to anon, authenticated, service_role;
alter default privileges in schema xix grant all on tables to service_role;
alter default privileges in schema xix grant all on sequences to service_role;
alter default privileges in schema xix grant execute on functions to service_role;

-- profiles: one per auth user, created by ensure_profile(); never by a trigger on auth.users.
create table xix.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text,
  is_anonymous  boolean not null default true,      -- mirrors auth.users.is_anonymous
  level_auto    numeric(4,1),                       -- rolling avg vs par; null until 3 rounds
  level_index   numeric(4,1),                       -- user-entered index, overrides
  created_at    timestamptz not null default now()
);

-- Profiles are created lazily by xix.ensure_profile() (0010) on the caller's first XIX action.
-- Nothing in this schema touches auth.users: the Supabase project is shared with other apps.

-- courses: free text, no match required; global merge is a later concern.
create table xix.courses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  region      text,
  osm_id      bigint,
  created_by  uuid references xix.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique nulls not distinct (name, region, created_by)
);

create table xix.course_holes (
  course_id     uuid not null references xix.courses (id) on delete cascade,
  hole          smallint not null check (hole between 1 and 18),
  par           smallint check (par between 3 and 6),
  stroke_index  smallint check (stroke_index between 1 and 18),
  yards         integer check (yards > 0),
  primary key (course_id, hole)
);

grant select, insert, update on xix.profiles to authenticated;
grant select, insert, update on xix.courses to authenticated;
grant select, insert, update on xix.course_holes to authenticated;
