# XIX — Build Document 1: Data Model and Scoring Engine

**Version:** 1.0 · 12 September 2026  
**Source of truth:** PRD v0.3, Claude Design Passes 5–7  
**Scope:** the Supabase schema and RLS, and the pure-Swift scoring module with its contracts, algorithms, edge cases and test fixtures. No UI, no sync logic (Build Document 2).

---

## Part A — Data model (Supabase / Postgres)

### A.1 Principles

- One round is the unit of everything. Every score, game, callout, sticker and medal hangs off a `round_id`.
- **Rows are owned.** A `player` row belongs to a `profile` once claimed; until then it belongs to the round owner. RLS enforces "write your own row; owner writes any row".
- **Scores are facts, results are derived.** Game outcomes, medals and Rival Points are computed by the scoring engine from `scores` and stored only as a cache (`results`) that can be rebuilt at any time.
- **Stickers are speech.** A sticker row always has a `sender_player_id`. There is no system sender.
- **No money fields anywhere.** No stake, amount, currency, owed, settled columns. Lint the schema for these words.

### A.2 Tables

```
profiles
  id uuid pk (= auth.users.id)
  display_name text
  is_anonymous bool             -- Supabase anonymous auth; linked later
  level_auto numeric(4,1)       -- rolling avg vs par, null until 3 rounds
  level_index numeric(4,1)      -- user-entered index, overrides
  created_at timestamptz

courses
  id uuid pk
  name text                     -- free text; no match required
  region text                   -- optional ("Vancouver")
  osm_id bigint                 -- optional
  created_by uuid fk profiles
  created_at timestamptz
  unique (name, region, created_by)  -- avoid dupes per user; global merge later

course_holes
  course_id uuid fk courses
  hole smallint (1..18)
  par smallint                  -- nullable (par optional)
  stroke_index smallint         -- nullable
  yards int                     -- nullable
  pk (course_id, hole)

rounds
  id uuid pk
  owner_id uuid fk profiles
  course_id uuid fk courses
  played_on date
  holes smallint (9|18)
  status text ('setup','live','ended')
  join_code text unique         -- xix.golf/r/{code}
  ended_at timestamptz
  created_at timestamptz

players                         -- one row per person in the round
  id uuid pk
  round_id uuid fk rounds
  profile_id uuid fk profiles   -- null until claimed
  display_name text
  seat smallint (0..3)
  level_snapshot numeric(4,1)   -- Level at round start, for net games
  claimed_at timestamptz
  left_at timestamptz

scores
  round_id uuid fk rounds
  player_id uuid fk players
  hole smallint
  strokes smallint              -- null = not entered; 1..; see picked_up
  picked_up bool default false  -- if true, strokes is ignored; engine applies max
  entered_by uuid fk profiles
  updated_at timestamptz        -- last-write-wins key
  pk (round_id, player_id, hole)

games                           -- one row per activated game in a round
  id uuid pk
  round_id uuid fk rounds
  format text                   -- enum, see Part B
  options jsonb                 -- e.g. {"carryover":true,"validation":false}
  created_at timestamptz

game_players
  game_id uuid fk games
  player_id uuid fk players
  side smallint                 -- team formats: 0/1; individual: null
  pk (game_id, player_id)

callouts
  id uuid pk
  round_id uuid fk rounds
  hole smallint
  kind text ('target','duel','partner','multiplier')
  caller_id uuid fk players
  target_ids uuid[]             -- one player, or all others
  params jsonb                  -- target: {"goal":"par"|"birdie"|n}; duel: {}; partner: {"partner_id"|null}; multiplier: {"game_id", "factor":2}
  status text ('open','signed','ducked','expired','resolved')
  responder_id uuid fk players  -- who signed/ducked
  responded_at timestamptz
  created_at timestamptz

stickers
  id uuid pk
  round_id uuid fk rounds
  hole smallint
  target_player_id uuid fk players
  sender_player_id uuid fk players   NOT NULL
  sticker_key text              -- 'YIKES', 'CLUTCH', ...
  pack_key text default 'base'
  played_at timestamptz         -- recipient tapped it
  created_at timestamptz

results                         -- engine output cache, rebuildable
  round_id uuid fk rounds
  version int                   -- engine version that produced it
  payload jsonb                 -- RoundResult (Part B.3)
  computed_at timestamptz
  pk (round_id)

medals
  id uuid pk
  profile_id uuid fk profiles
  round_id uuid fk rounds
  key text                      -- 'nassau_front', 'skins_two', 'callout_called_it', ...
  opponent_profile_id uuid      -- nullable
  context jsonb                 -- {"course":"Fraserview","date":"2026-09-09","holes":[4,9]}
  created_at timestamptz

confirmations
  round_id uuid fk rounds
  profile_id uuid fk profiles
  action text ('confirm','object')
  created_at timestamptz
  pk (round_id, profile_id)

crews / crew_members             -- private boards
  crews: id, name, owner_id, created_at
  crew_members: crew_id, profile_id, joined_at

ranking_entries                  -- materialised nightly
  profile_id, metric text, window text, value numeric, computed_at
```

### A.3 RLS (essentials)

- `rounds`: readable by any `players.profile_id` in the round or by join_code lookup (via RPC); writable by owner.
- `players`: readable by round members; insert/update by owner; a member may update only their own row's `display_name` after claiming; `claimed_at` set via RPC `claim_row(round_id, player_id)` which requires the row be unclaimed.
- `scores`: insert/update allowed if (a) `player_id` is the caller's own row, or (b) caller is round owner. Read for members.
- `games`, `game_players`: owner only, and only while `rounds.status = 'setup'` or no `scores` exist for hole 1 (enforced in RPC `set_games`).
- `callouts`: insert by any member for a hole with no scores yet; update `status/responder_id` only by a member in `target_ids`; expiry set by trigger when a score lands on that hole.
- `stickers`: insert by any member; `sender_player_id` must equal the caller's own row (trigger); cap 3 per hole per sender (trigger); `played_at` updatable only by the target.
- `results`: written by the engine (service role or edge function); read by members.
- `medals`: read own; written by engine.
- `confirmations`: insert own; one per profile per round.

### A.4 Triggers

- `expire_callouts_on_score`: on insert/update of `scores`, set any `callouts.status='open'` for that hole to `'expired'`.
- `sticker_rate_limit`: reject the 4th sticker per (round, hole, sender).
- `recompute_results`: on any change to `scores`, `games`, `game_players`, `callouts` for a round → enqueue engine run (edge function) → upsert `results`. Client also computes locally for instant UI; server result is authoritative for medals and rankings.
- `auto_confirm`: nightly job marks rounds ended > 48h with ≥ 1 confirmation or no objection as counted.

---

## Part B — Scoring engine (Swift package `XIXScoring`)

### B.1 Design

- Pure functions, no I/O, no Date.now. Deterministic given inputs. Same package runs on device and in the edge function (compiled to a JS/Wasm target later; for V1 the edge function can call a Swift-on-Linux binary or a transpiled TS port — decide in Build Doc 2; the fixtures in B.7 make either port verifiable).
- Input: `RoundInput`. Output: `RoundResult`. Engine version stamped on output.
- Partial rounds are first-class: every result is computable at any hole, with `status: .inProgress` and running standings.

### B.2 Input contract

```swift
struct RoundInput {
  let holes: Int                       // 9 or 18
  let par: [Int?]                      // per hole, nil if unknown
  let strokeIndex: [Int?]              // per hole, nil if unknown
  let players: [PlayerInput]           // seat order
  let scores: [[HoleScore?]]           // [player][hole]; nil = not entered
  let games: [GameInput]
  let callouts: [CalloutInput]
}
enum HoleScore { case strokes(Int), pickedUp }
struct PlayerInput { let id: PlayerID; let level: Double? }   // Level 1–10 or index; nil = none
struct GameInput { let id: GameID; let format: Format; let options: Options; let players: [PlayerID]; let sides: [PlayerID: Int]? }
struct CalloutInput { let id: CalloutID; let hole: Int; let kind: CalloutKind; let caller: PlayerID; let targets: [PlayerID]; let params: CalloutParams; let status: CalloutStatus }
```

### B.3 Output contract

```swift
struct RoundResult {
  let engineVersion: Int
  let status: RoundStatus               // .inProgress(throughHole) | .complete
  let perPlayer: [PlayerID: PlayerSummary]   // gross, toPar (nil if any par nil), holesEntered, marks per hole
  let games: [GameResult]
  let callouts: [CalloutResult]
  let holeEvents: [HoleEvent]           // ink lines: "Skin to Tess. Carry cleared."
  let medals: [MedalAward]              // only when .complete
  let rivalPoints: [PlayerID: Int]      // only when .complete
  let leaderboard: [LeaderboardMode: [LeaderboardRow]]
}
struct GameResult { let gameID: GameID; let format: Format; let standings: [Standing]; let outcome: Outcome? /* nil until complete */; let display: GameDisplay /* "Skins 2", "Nassau 1 up" per player */ }
```

### B.4 Normalisation rules (applied before any format)

1. **Picked up** → effective strokes = `2 × par[hole]` when par known; if par unknown → `10`. Stableford-style points for that hole = 0 regardless.
2. **Missing score** → the hole is *unresolved* for every game that includes that player. Games report standings "through hole n" where n is the last hole at which all participating players have scores. Skins with an unresolved hole stop carrying forward until resolved.
3. **Marks (ink)** per hole per player: `circle` if strokes ≤ par−1, `square` if strokes == par+1, `filled` if strokes ≥ par+2, none otherwise; `x` if picked up. No marks when par is nil.
4. **Net strokes** (net formats only): handicap strokes allocated by stroke index when known, else evenly from hole 1. Level → strokes: `round((10 − level) × 2.4)` clamped 0–24 (Level 10 = 0 strokes, Level 1 ≈ 22). A user-entered index overrides: strokes = round(index). Level nil → net formats unavailable (engine returns `.unavailable(reason)`).
5. **toPar** is nil for the round if any played hole has nil par; per-hole toPar still computed where par exists.

### B.5 Formats

Each format defines `standings(throughHole)` and `outcome()`; ties are explicit, never broken silently.

**Stroke Play** — sum of effective strokes (gross or net). Outcome: lowest; ties shared.

**Stableford** (par required) — per hole: net strokes vs par → points {≤−2:4, −1:3, 0:2, +1:1, ≥+2:0}; picked up → 0. Highest total wins. Variant `modified` (options) uses {8,5,2,0,−1,−3} — not in V1 UI, keep the table pluggable.

**Match Play** — two sides (players or teams via best ball). Per hole: lower net wins hole, equal halves. Standing = holes up and holes to play; match ends when up > remaining (report "3&2"). Outcome: winner, or halved.

**Nassau** — three Match Play instances: holes 1–9, 10–18, 1–18. Each resolves independently. Display per player "1 up front" etc. Options: `presses: false` (V1 has no presses).

**Skins** — per hole, unique lowest (gross or net per options) wins `1 + carried` skins; tie → carry += 1. Options: `carryover` (default true), `validation` (a carried pot is only won if the winner also scores par or better; else carry continues). At round end, unclaimed carry is void. Standing: skins per player, current carry. Hole event: "Skin to Tess. Carry cleared." / "Halved. 2 carrying to 13."

**Best Ball / Four-Ball** — sides of 2; side score per hole = min of members; then Stroke Play or Match Play per options (`mode`).

**Scramble / Shamble / Alternate Shot / Chapman** — one score row per side (the players enter a single side score; `sides` maps members → side and the side's "player" row carries the strokes). Engine treats as Stroke Play across sides. Shamble option `count: 1|2` best scores when members enter individually.

**Vegas** — sides of 2. Side number per hole = concat(low, high) e.g. 4 and 5 → 45. Points to the lower side = difference. Birdie flip: if a side has a member with strokes ≤ par−1, the opposing side's digits are reversed (high first) before differencing. Picked up counts as its effective strokes. Standing: cumulative points per side.

**Nines (9 Points)** — exactly 3 players. Per hole allocate 9 points by finish: 5/3/1; ties split: two tied low → 4/4/1; two tied high → 5/2/2; all tied → 3/3/3. Highest total wins.

**Sixes (Round Robin)** — 4 players; three 6-hole Best Ball match plays with rotating partners (1–6: AB v CD, 7–12: AC v BD, 13–18: AD v BC). Points per segment: win 2, halve 1. Highest wins.

**Quota / Chicago** (Level required) — per player quota = `36 − handicapStrokes` (min 0). Points per hole gross: bogey 1, par 2, birdie 4, eagle 8, else 0. Result = points − quota. Highest wins.

**Rabbit** — per hole, unique lowest takes the rabbit; tie → rabbit stays where it is; if a different player wins outright the rabbit moves. Holder after hole 9 and after final hole are the outcomes (two awards).

**Defender** — 3 players; rotating defender vs best ball of the other two each hole; defender wins hole → +2 defender; loses → +1 each attacker; halve → 0. Highest wins.

**Casual-first**
- *Fewest Blow-Ups* (par): points per hole = 1 if strokes ≤ par+1 else 0 (picked up = 0). Highest.
- *Beat Your Average* (needs ≥3 prior rounds; input `priorAverage` per player in `PlayerInput.extras`): result = priorAverage − gross; highest (most improved) wins.
- *Bogey Golf* (par): Stableford with par redefined as par+1.
- *Most Pars* (par): count of strokes == par (gross). Highest.
- *First to Five* (par): first player (by hole order) to reach five holes at ≤ par; if none, most such holes; ties by earlier hole reached.
- *Worst Hole*: per player, max(strokes − par) hole; the round's single worst (strokes − par) across players is the award; ties → all tied share. Nickname is UI, not engine.

**Passive ranking metrics** (computed per player, outside games): Stableford vs Level (needs par and Level), birdies count, rounds played (counter), Rival Points.

### B.6 Callouts

Resolve only if `status == .signed` at the time the hole's scores are complete. `open` → becomes `expired` when the hole resolves without signature. `ducked` → no result; recorded as ducked by responder.

- **Target** `goal ∈ {par, birdie, n}`: each target player hits if effective strokes ≤ goal. Any hit → hitters win; none → caller wins.
- **Duel**: caller vs single target on the hole; lower wins; tie → halved.
- **Partner** (one-hole Wolf): caller (+ partner if any) vs the rest; best ball per side; lower wins; tie halved. Lone caller who wins earns `double` in the callout medal set.
- **Multiplier**: applies `factor` to the referenced game on that hole only — Skins: hole worth `factor` skins; Match Play/Nassau: hole counts as `factor` holes up; Stableford/Stroke: points/strokes difference on that hole × factor in standings. Never alters other games.

### B.7 Medals and Rival Points (on `.complete` only)

Medal keys (V1): `nassau_front`, `nassau_back`, `nassau_18`, `skins_two` (≥2 skins in a round), `skins_four`, `matchplay_win`, `stableford_top`, `stroke_low_gross`, `five_pars`, `no_blowups`, `beat_average`, `callout_called_it` (target won as caller), `callout_duel`, `callout_lone_wolf`, `callout_ducked_nothing` (signed every callout received, ≥2), `rabbit_9`, `rabbit_18`, `personal_best` (needs history input).

Rival Points: for each game outcome, winner(s) receive `base(format) × opponentFactor`, where `base` = 10 (individual formats), 6 (team formats), 4 (casual-first), 3 (callout); `opponentFactor = 1 + 0.1 × max(0, opponentLevel − ownLevel)` using the strongest opponent; halved → half to each side. Ducked callouts give 0 to everyone. Points are integers (rounded).

### B.8 Edge cases (must have tests)

1. Round with par nil on some holes: Stableford unavailable; Skins/Match/Nassau fine; toPar nil; marks only where par exists.
2. Player leaves after hole 6: their games report `.abandoned(byPlayer)`; skins they hold stay; Nassau vs them ends as `.void`.
3. All four tie every hole in Skins → 18 carry, void at end, zero skins to all.
4. Skins with validation: carry of 3 won by a bogey → not awarded, carry continues.
5. Picked up on a par-5 → 10 strokes; Stableford 0; Vegas digit is 10 → treat as two-digit component using effective strokes capped at 9 for digit concat (document: cap 9 for Vegas only).
6. Match Play decided early (5&4): remaining holes don't change the result; standings freeze.
7. Nassau 18 halved while front and back split.
8. Nines with two tied high on a hole → 5/2/2.
9. Multiplier callout on a Skins hole that is then halved → carry increases by `factor`.
10. Target callout to "crew" where the caller also hits the target → caller does not count as a target; only targets can hit.
11. Callout signed then a score lands on that hole from another player before the target plays: still valid (signature was before any score on that hole for the callout's participants — rule: expiry is triggered by the first score *from a participant*).
12. 9-hole round: Nassau unavailable (needs 18); Sixes unavailable; Rabbit awards at 9 only.
13. Two players only: Skins/Nines/Sixes unavailable (Skins allowed at 2? → allowed; Nines requires exactly 3; Sixes exactly 4).
14. Level present for some players, absent for others → net formats unavailable for that game unless every participant has a Level.
15. Scores edited after results computed → results recompute; medals are re-derived, never duplicated (idempotent by (profile, round, key)).

### B.9 Test fixtures

Provide as JSON under `Tests/Fixtures/`:
- `fraserview_2026-09-09.json` — the four-player round used in every design pass (Ray 78, Dave 84, Mo 88 with one picked-up, Tess 78), games: Nassau (Ray–Dave), Skins (all, carryover, no validation), Stableford (Mo–Tess); callouts: target par on 8 (Ray→Dave, signed, nobody hit → Ray wins), target par on 12 (Ray→Dave, ducked). Expected: Nassau front Ray 1 up, back Dave, 18 halved; Skins Ray 2, Tess 2, Dave 1, Mo 0 with 1 carry void; medals `nassau_front` (Ray), `skins_two` (Ray, Tess), `callout_called_it` (Ray).
- `two_player_matchplay.json` — decided 4&3.
- `nine_hole_no_par.json` — par nil, skins only.
- `vegas_birdie_flip.json`, `nines_ties.json`, `sixes_rotation.json`, `quota.json`, `rabbit_moves.json`, `pickup_par5.json`, `abandon_hole6.json`, `multiplier_halved.json`.

Every fixture has an `expected` block; the test runner compares `RoundResult` field-by-field with tolerance only on Rival Points rounding.

### B.10 Versioning

`engineVersion` increments on any rule change. `results.version` lets the server recompute historical rounds when a rule is fixed; medals already awarded are never revoked by a recompute (append-only), only added.

---

## Part C — Open items for Build Document 2 (sync and UI)

- Edge-function runtime for the engine (Swift on Linux vs TS port with shared fixtures).
- Realtime channel shape per round; offline queue and merge notice.
- Anonymous auth → account linking flow (email / Sign in with Apple).
- Course table merge strategy (same name/region across users) and OSM lookup.
- Rive asset loading and sticker pack entitlement checks.
