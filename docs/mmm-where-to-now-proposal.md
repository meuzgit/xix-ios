# Where to now — proposed migration 0021, for MMM's schema owner

**Status: a proposal. Nothing has been applied anywhere, and the SQL is deliberately not in `supabase/migrations/` so that no `db push` can pick it up.** The draft is `docs/proposed/0021_where_to_now.sql`. It is written against an *assumed* shape for MMM's tables, because I do not have MMM's schema; every assumption is listed below with the question it needs answered. Once the real column names come back, the only part that changes is the mapping block in the middle of the function.

This is the one place XIX touches MMM (Build Doc 3 step 4, PRD 8.10). It reads. It never writes, and it never restyles.

## 1. What the screen renders, and therefore what XIX needs back

The feed is MMM's, reproduced as built (PRD 8.10; Pass 5 5f; Pass 6 6h). XIX adds a tracked-caps "WHERE TO NOW?" line above it and the yellow "Open in My Main Man" button below it, and nothing else. So the output contract is fixed by what MMM's own cards draw:

| Output column | Type | Where it is drawn | Notes |
|---|---|---|---|
| `place_id` | uuid | the deep link to MMM | the tap target for every card |
| `name` | text | hero and grid cards | |
| `city` | text | under the name | Pass 5 draws "name, city" |
| `category` | text | the Eat / Drink pills | **only `eat` and `drink` are ever returned** |
| `illustration` | text | the watercolour | a URL or a storage key; see question 3 |
| `distance_m` | integer | "drive-time · distance" | from the course's position |
| `drive_minutes` | integer | "drive-time · distance" | see question 4 — XIX cannot compute this |
| `is_open` | boolean | the OPEN badge and the status dot | |
| `status_line` | text | the status line under a grid card | MMM's own wording, not XIX's |
| `liked` | boolean | the filled-heart action icon | the signed-in user's own state |
| `bookmarked` | boolean | the bookmark action icon | the signed-in user's own state |
| `from_circle` | boolean | "Two of these come from your circle" | PRD 8.10: a group's circle surfaces first |
| `rank` | integer | the order of the cards | MMM's own ordering, never XIX's |

And three values about the feed as a whole, so the locked and empty states can be MMM's own:

| Output | Type | Why |
|---|---|---|
| `entitled` | boolean | whether this user sees the whole feed |
| `allowance_remaining` | integer | the locked card's copy must mirror MMM's real rule, not invent one |
| `allowance_period` | text | e.g. `week` — same reason |

## 2. Every MMM table and column the draft reads

This is the list to check. The left column is what the draft assumes; the right is the question. Nothing here is asserted as fact.

### `mmm.places` — one row per place

| Assumed column | Used for | Confirmed? |
|---|---|---|
| `id` | `place_id` | ? |
| `name` | `name` | ? |
| `city` | `city` | ? |
| `category` | the eat/drink filter and `category` | ? — and what are its exact values? |
| `illustration_path` | `illustration` | ? — a public URL, or a storage key XIX must sign? |
| `lat`, `lng` | `distance_m` | ? — or is it a PostGIS `geography` column? |
| `status_line` | `status_line` | ? — stored, or derived from hours? |
| `published_at` / `is_visible` | excluding drafts and hidden places | ? — how does MMM decide a place is live? |

### `mmm.place_hours` — opening hours, if `is_open` is not stored

| Assumed column | Used for | Confirmed? |
|---|---|---|
| `place_id`, `weekday`, `opens_at`, `closes_at` | `is_open` | ? — or does MMM already expose an `is_open` / `open_now` it would rather XIX used? |

### `mmm.likes` and `mmm.bookmarks` — the user's own marks

| Assumed column | Used for | Confirmed? |
|---|---|---|
| `profile_id`, `place_id` | `liked`, `bookmarked` | ? — two tables, or one with a `kind`? |

### MMM's entitlement — the part XIX must not invent

| Assumed source | Used for | Confirmed? |
|---|---|---|
| `mmm.subscriptions(profile_id, status, current_period_end)` | `entitled` for an Insider | ? |
| `mmm.place_views(profile_id, place_id, viewed_at)` | the free allowance already spent | ? |
| MMM's allowance rule | `allowance_remaining`, `allowance_period` | ? — **what is the real rule?** The copy has to mirror it exactly |

### The circle

| Assumed source | Used for | Confirmed? |
|---|---|---|
| `mmm.follows(profile_id, followed_profile_id)` + `mmm.likes` | `from_circle` | ? — how does MMM decide a recommendation is "from your circle"? |

## 3. Open questions for MMM's schema owner

1. **Is a function acceptable, or must this be a plain view?** Build Doc 3 says `xix.where_to_now(lat, lng, category)`, which takes arguments, so the draft is a `STABLE SECURITY DEFINER` set-returning function. If MMM would rather XIX read a view MMM owns and controls, that is better for you: XIX would select from it and this function would shrink to a thin wrapper. Say which and I will write it that way.
2. **Who owns the entitlement logic?** The draft evaluates it inline, which means XIX's function would have to change whenever MMM's rule changes. A function in MMM's own schema — `mmm.feed_entitlement(profile_id)` returning `(entitled, remaining, period)` — would keep that rule where it belongs and leave XIX reading an answer instead of re-deriving one. **This is my recommendation.**
3. **Illustrations:** public URL, or a storage key that needs signing? If the latter, XIX needs to know which bucket and whether MMM's policy allows XIX's users to read it.
4. **Drive time:** XIX can compute distance from the course's coordinates, but not drive minutes. Does MMM store a drive time, or compute it through a routing service at query time? If neither is available to XIX, the card shows distance alone and the design needs a one-line decision from you.
5. **Does a view of a place count against the allowance, and does reading it through XIX count?** The draft does not write anything, so it cannot record a view. If MMM's allowance is consumption-based, MMM needs to own that write, and XIX would call an MMM function rather than a view.
6. **Which position does the feed take?** The course's coordinates come from `xix.courses` once the OSM enrichment job in step 8 fills them, or from the device at round end with permission. Until then the caller passes a position explicitly.

## 4. It runs — against the stand-in, not against MMM

The draft is not just written, it is exercised. Applied to the local database over the seeded shape:

```bash
supabase db reset                                     # brings up the stand-in shape and its rows
docker exec -i supabase_db_XIX psql -U postgres -d postgres -f - < docs/proposed/0021_where_to_now.sql
```

Ray, who is not an Insider and has spent one of his three this week, asking from Fraserview:

| name | category | distance_m | drive_minutes | is_open | from_circle | rank | entitled | allowance_remaining | allowance_period |
|---|---|---|---|---|---|---|---|---|---|
| Kinsman | drink | 956 | 6 | yes | yes | 1 | no | 2 | week |
| Katsu House | eat | 1913 | 9 | yes | yes | 2 | no | 2 | week |

Two rows, because two is what MMM's allowance leaves him, and the two his circle liked come first. Dave, an Insider, gets all five with `entitled` true and no allowance. Filtering to `drink` returns the two drink places. Asking for `stay` is refused: "where to now covers eat and drink".

Applying it by hand like that puts a security-definer function in `xix` that no migration created, which the census test in `17_security_definer.test.sql` will fail on. `make pgtap` resets first so it never sees it, but drop it when you are done poking at it:

```bash
docker exec -i supabase_db_XIX psql -U postgres -d postgres \
  -c "drop function if exists xix.where_to_now(double precision, double precision, text); drop type if exists xix.where_to_now_row;"
```

That proves the shape of the thing — the entitlement cut, the ordering, the eat/drink filter, the caller-scoped likes — against assumptions. It proves nothing about MMM's real tables, which is what the questions above are for.

## 5. What is safe to build meanwhile

`supabase/seeds/mmm_shape.sql` creates the assumed shape and a handful of places on the **local stack only**, so the function, the screen and their tests can be built and run now. It is a stand-in, not a copy of MMM's data, and it never runs anywhere but a local `db reset`.

When the real columns come back, the mapping block in `docs/proposed/0021_where_to_now.sql` changes, the seed changes to match, and the output contract in §1 stays exactly as it is — which is the point of putting the projection in one place.
