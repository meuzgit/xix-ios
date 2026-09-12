-- PROPOSED, NOT APPLIED. This file lives in docs/proposed/ on purpose: it is not in
-- supabase/migrations/, so no `supabase db push` can pick it up. It moves there only after MMM's
-- schema owner has confirmed the columns in docs/mmm-where-to-now-proposal.md.
--
-- 0021: Where to now (Build Doc 3 step 4, PRD 8.10). The MMM feed, read by XIX and rendered as MMM
-- built it. This is the only place XIX touches MMM. It reads; it never writes.
--
-- Everything between the two MAPPING markers is written against an assumed shape for MMM's tables and
-- is the only part that changes once the real names come back. The columns the function returns are
-- fixed by what MMM's own cards draw, and do not change.

-- The feed's shape: exactly what the hero card and the grid cards render, and the three values the
-- locked and empty states need. Nothing else leaves MMM through here.
create type xix.where_to_now_row as (
  place_id            uuid,
  name                text,
  city                text,
  category            text,      -- 'eat' or 'drink', never anything else
  illustration        text,
  distance_m          integer,
  drive_minutes       integer,   -- null when MMM has no drive time to give (see question 4)
  is_open             boolean,
  status_line         text,      -- MMM's wording
  liked               boolean,
  bookmarked          boolean,
  from_circle         boolean,
  rank                integer,   -- MMM's ordering
  entitled            boolean,
  allowance_remaining integer,
  allowance_period    text
);

-- xix.where_to_now(lat, lng, category)
--
-- SECURITY DEFINER because MMM's tables are not readable by XIX's roles directly; STABLE because it
-- only reads. The caller's identity comes from auth.uid() and nothing else: a caller cannot ask for
-- somebody else's likes, allowance or circle.
--
-- Entitlement is evaluated inside, as Build Doc 3 requires. An Insider gets the whole feed. A
-- non-Insider gets MMM's free allowance and then the gate, and the row count matches the allowance so
-- the screen cannot show more than MMM would. `entitled`, `allowance_remaining` and `allowance_period`
-- ride on every row so the locked card can mirror MMM's real rule instead of inventing one.
create or replace function xix.where_to_now(lat double precision, lng double precision, category text default null)
returns setof xix.where_to_now_row
language plpgsql
stable
security definer
set search_path = xix, mmm, public, pg_temp
as $$
declare
  me uuid := auth.uid();
  is_insider boolean := false;
  spent integer := 0;
  allowance integer;
  period text;
  cap integer;
begin
  if me is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;
  if category is not null and category not in ('eat', 'drink') then
    raise exception 'where to now covers eat and drink' using errcode = '22023';
  end if;

  -- ===== MAPPING START — assumed MMM shape, to be confirmed =====
  -- Recommended alternative: replace this whole block with one call to an MMM-owned function, e.g.
  --   select entitled, remaining, period into is_insider, allowance, period from mmm.feed_entitlement(me);
  -- so MMM's rule stays inside MMM and XIX reads an answer rather than re-deriving one.
  select exists (
    select 1 from mmm.subscriptions s
     where s.profile_id = me and s.status = 'active' and s.current_period_end > now()
  ) into is_insider;

  select coalesce(mmm.free_allowance_per_period(), 3), coalesce(mmm.free_allowance_period(), 'week')
    into allowance, period;

  select count(*) into spent
    from mmm.place_views v
   where v.profile_id = me
     and v.viewed_at >= date_trunc(period, now());
  -- ===== MAPPING END =====

  cap := case when is_insider then null else greatest(allowance - spent, 0) end;

  return query
  with nearby as (
    -- ===== MAPPING START — assumed MMM shape, to be confirmed =====
    select
      p.id                                   as place_id,
      p.name                                 as name,
      p.city                                 as city,
      p.category                             as category,
      p.illustration_path                    as illustration,
      -- Distance on the sphere, in metres. No PostGIS assumed; if MMM stores geography, this becomes
      -- ST_Distance and gets an index behind it.
      (6371000 * acos(least(1, greatest(-1,
        cos(radians(where_to_now.lat)) * cos(radians(p.lat)) *
        cos(radians(p.lng) - radians(where_to_now.lng)) +
        sin(radians(where_to_now.lat)) * sin(radians(p.lat))
      ))))::integer                          as distance_m,
      p.drive_minutes                        as drive_minutes,
      p.is_open                              as is_open,
      p.status_line                          as status_line,
      exists (select 1 from mmm.likes l where l.place_id = p.id and l.profile_id = me)      as liked,
      exists (select 1 from mmm.bookmarks b where b.place_id = p.id and b.profile_id = me)  as bookmarked,
      exists (
        select 1 from mmm.likes l
          join mmm.follows f on f.followed_profile_id = l.profile_id
         where l.place_id = p.id and f.profile_id = me
      )                                      as from_circle,
      p.rank                                 as source_rank
    from mmm.places p
   where p.category in ('eat', 'drink')
     and (where_to_now.category is null or p.category = where_to_now.category)
     and p.is_visible
    -- ===== MAPPING END =====
  ),
  ordered as (
    -- MMM's own ordering: the circle first where it exists, then MMM's area intelligence (PRD 8.10).
    -- XIX never re-ranks and never hand-curates.
    select nearby.*,
           row_number() over (order by from_circle desc, source_rank asc nulls last, distance_m asc)::integer as rank
      from nearby
  )
  select o.place_id, o.name, o.city, o.category, o.illustration, o.distance_m, o.drive_minutes,
         o.is_open, o.status_line, o.liked, o.bookmarked, o.from_circle, o.rank,
         is_insider as entitled,
         case when is_insider then null else greatest(allowance - spent, 0) end as allowance_remaining,
         case when is_insider then null else period end as allowance_period
    from ordered o
   where cap is null or o.rank <= cap   -- a non-Insider never receives more than MMM would show them
   order by o.rank
   limit 60;
end;
$$;

-- XIX's users read it; nobody else does, and anon never does.
revoke execute on function xix.where_to_now(double precision, double precision, text) from public, anon;
grant execute on function xix.where_to_now(double precision, double precision, text) to authenticated;

-- Note for the census test (17_security_definer): where_to_now is security definer and reads MMM, so
-- it joins the list with an explicit note that it is readable by authenticated users only, takes the
-- caller from auth.uid(), and writes nothing.
