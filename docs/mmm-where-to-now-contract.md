# Where to now — the response contract XIX renders

**Step 4 is parked until MMM's endpoint exists.** This document is the one thing XIX needs from MMM, and it is deliberately small.

XIX is a window, not a participant. It reads none of MMM's tables, holds none of MMM's rules, and computes none of MMM's numbers. An earlier draft of this document proposed a view over MMM's tables with MMM's entitlement re-derived inside it; that approach is discarded, along with its table-by-table assumptions and its `0021` migration. What replaces it is a single MMM-owned endpoint.

## The endpoint

```
mmm.feed_for_xix(profile_id uuid, lat double precision, lng double precision, category text default null)
```

MMM owns it: MMM's filtering to eat and drink, MMM's ordering, MMM's drive time and distance, MMM's entitlement, MMM's copy. XIX passes who is asking and where they are, and renders what comes back.

`category` is `eat`, `drink`, or null for both. Anything else is MMM's to refuse.

## What comes back

The fields are fixed by what MMM's own cards draw (PRD 8.10; Pass 5 5f; Pass 6 6h), because XIX reproduces the feed as built and adds only a tracked-caps "WHERE TO NOW?" line above it and the yellow "Open in My Main Man" button below.

### Per place

| Field | Type | Drawn as |
|---|---|---|
| `place_id` | uuid | the deep link target for the card |
| `name` | text | hero and grid cards |
| `city` | text | under the name |
| `category` | text | the Eat / Drink pills |
| `illustration` | text | the watercolour — a URL XIX can load without credentials |
| `distance` | text | the "drive-time · distance" line, in MMM's own words and units |
| `drive_time` | text | the same line, MMM's words |
| `is_open` | boolean | the OPEN badge and the status dot |
| `status_line` | text | the status line under a grid card, MMM's wording |
| `liked` | boolean | the filled-heart icon, for the connected user |
| `bookmarked` | boolean | the bookmark icon |
| `from_circle` | boolean | "two of these come from your circle" |

Distance and drive time are text, not numbers, so that the units, the rounding and the wording stay MMM's. XIX never formats them.

### About the feed

| Field | Type | What XIX does with it |
|---|---|---|
| `state` | text | `ok`, `gated`, or `empty` |
| `gate_title` | text | the locked card's heading, when gated |
| `gate_body` | text | its body, which must be MMM's real allowance rule |
| `gate_action` | text | the yellow button's label |
| `gate_url` | text | where that button goes |
| `empty_message` | text | MMM's one-line empty message |
| `header` | text | MMM's own header line, e.g. "Vancouver through My Main Man" |

XIX renders the gate as sent: MMM's card, MMM's copy, MMM's action. It never writes that copy, never invents an allowance rule, and never offers XIX Full in its place.

## The connection

Where to now is gated on the MMM connection and nothing else.

- Settings carries a "My Main Man" toggle. Switching it on runs MMM's own authentication and stores a revocable per-user connection; switching it off removes it and nothing else changes.
- Connected, the feed appears after a round. Not connected, or no MMM account at all, and the feed is simply absent.
- XIX's own account and XIX Full have nothing to do with it. A user with no relation to MMM uses the whole app normally.
- The unconnected state is an invitation to connect, never a paywall.

## What XIX still owes this

- A thin RPC in `xix` that calls the endpoint with `auth.uid()` as `profile_id`, so a caller can only ever ask about themselves. It carries no rules of its own.
- The connection record and the Settings toggle.
- `MMMFeedKit`: MMM's design tokens for this screen only, a small package extracted from MMM or a faithful copy pinned to its version.
- A local stub of the endpoint, shaped like the response above, so the screen can be built and tested before MMM's is live.

All four wait for the endpoint.
