# Build Doc 3 · Step 5 acceptance — cabinet, rivalry, rankings, crews

*Acceptance: after three rounds across two accounts, both rivalry and both boards show correct numbers against a hand tally.*

`XIXData/Tests/XIXDataTests/RankingsAcceptanceTests.swift` plays those three rounds through the same path the app uses — real RPCs, the engine running on the server through the webhook, the nightly ranking job — and checks every number against a tally worked out on paper first. Run it with `make rankings-acceptance`.

## The three rounds

Nine holes, par 4 throughout. Ray enters an index of 5, Dave an 8, the way Settings lets them; with no course stroke index the strokes fall in hole order, so Ray gets one on holes 1–5 and Dave one on holes 1–8.

| | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | gross |
|---|---|---|---|---|---|---|---|---|---|---|
| **R1** Ray | 3 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 35 |
| **R1** Dave | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 5 | 37 |
| **R2** Ray | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 36 |
| **R2** Dave | 3 | 3 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 34 |
| **R3** Ray | 3 | 3 | 3 | 4 | 4 | 4 | 4 | 4 | 4 | 33 |
| **R3** Dave | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 36 |

## The tally, and what the boards said

| Worked out by hand | Expected | The board |
|---|---|---|
| Head to head: Ray takes R1 (35 v 37) and R3 (33 v 36), Dave takes R2 (34 v 36) | Ray 2, Dave 1, over 3 rounds | ✓ and the same from Dave's side, the other way round |
| Birdies: Ray 1 + 0 + 3, Dave 0 + 2 + 0 | Ray 4, Dave 2 | ✓ Ray top of that board |
| Rounds played | 3 each | ✓ |
| Stableford vs Level, Ray: net 2,3,3,3,3,4,4,4,4 → 24; then 23; then 26 | 73 | ✓ |
| Stableford vs Level, Dave: net 3,3,3,3,3,3,3,3,5 → 25; then 28; then 26 | 79 | ✓ Dave top, on strokes |
| Rival Points: the engine's per-round totals, added up | the sum | ✓ |
| A crew of the two of them, ranked among themselves | Ray then Dave on birdies, ranks 1 and 2 | ✓ |

The screens that draw these are pinned separately by snapshots: the cabinet and its empty state, a medal's context card with the round it came from, the rivalry, both boards with the pending and frozen rows, and the two crew-creation steps.

## Three things this turned up

**Nothing ever wrote `players.level_snapshot`.** The column has existed since migration 0002, so every round was played by people the engine saw as having no Level at all: net games had nothing to work from and the passive Stableford metric the boards rank on could not be computed. A Level is now frozen onto the row as a player joins, and it stays as it was on the day whatever their Level does later.

**A Level and an index are different scales, and were about to be confused.** `profiles.level_auto` holds the Level XIX works out (1–10); `profiles.level_index` holds the index a player enters (0–54). The first version of the snapshot coalesced them into one column, which quietly turned an entered 5 into twelve strokes. They now travel in two columns, `round_input` sends both, and the engine applies the index in preference, as B.4.4 says it should.

**A round confirmed by another player did not start counting.** PRD 8.11 says a result counts when at least one other player confirms it, or automatically after 48 hours. Only the second half existed, so a round everybody had confirmed still sat out two days before reaching any board. A trigger now counts it on that confirmation, and an objection freezes it again.

All three are in migration 0021 with their own assertions in `21_cabinet_rivalry_rankings_crews.test.sql`.

## Notes

- `xix.refresh_rankings()` is the nightly job (03:20, after `auto_confirm`), callable by nobody else. The acceptance runs it directly as the service role rather than waiting for cron.
- Only rounds with `counted_at` reach a board, so an unconfirmed round is in nobody's ranking and in no rivalry.
- Medals from a round are now visible to everyone who played in it, not only to the person who won them — a rivalry has two sides, and under the old policy only one of them was readable.
- A crew board re-ranks its own members; ties share a rank, as the engine's own leaderboard does.
