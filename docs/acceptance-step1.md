# Build Doc 3 · Step 1 acceptance — two phones, one round, New round to results

Recorded on two simulators (iPhone 16 as Ray, the owner; iPhone 16 Pro as Dave, the guest) against the local Supabase stack with `supabase functions serve` answering the engine webhook. The taps are real: `XIX/UITests/PlayableLoopTests.swift` drives each phone, and `scripts/acceptance-video.sh` records both and stitches them side by side into `docs/acceptance-step1.mp4`.

## What the video shows

Left, Ray: Home (first run) → New round → Course "Fraserview", 9 holes → Par (hole 3 a par 3, hole 8 a par 5) → Players (Dave by name) → Games (Skins and Nassau, both rows) → Sign in asked for lazily at "Next" → Share the round (QR and link) → Play hole 1 → scores hole 1 for both rows → scores his own row through hole 9 → Grid → round menu → End round ("ALL 18 CELLS IN") → results with medals, games, callouts, highlights.

Right, Dave: opens the link after hole 1 (`xix://r/CODE`, the custom-scheme form of `xix.golf/r/CODE`) → Sign in → "RAY PUT YOU IN AS “DAVE”" → Claim this row → lands on hole 2, the current hole → scores his own row through hole 9 → the round ends on Ray's phone and Dave's phone moves to results on its own.

## Result

Recorded 11 September 2026 (local time), both UI tests passing in about 136 s each.

| Check | Result |
|---|---|
| Sign in asked for lazily (at "Next" on Games for Ray; on opening the link for Dave) | yes, both phones |
| Guest joins by link mid-round and lands on the current hole | Dave claimed his row after hole 1 and opened on hole 2 |
| Scores from both phones merge on both cards | every cell in on both, "ALL 18 CELLS IN" on End round |
| End round → results on the owner's phone | yes |
| Non-owner's phone moves to results on its own | yes, from the round row's Realtime change |
| Server result through the local engine webhook (pg_net → `supabase functions serve`) | `results.payload.status = complete`, 3 medals in `xix.medals`, queue empty |
| Results screen | headline gross, games line, medals as patches (Ray: Four Skins, Two Skins; Dave: Two Skins), games, highlights, Rival Points |

Not in the video: the result-link confirm (a guest scored by name opening the link after the round: Sign in → Confirm my scores → `claim_row` + `confirm_round`). It is built on the same join screen and covered by the results snapshot test; migration 0019 lets a join code resolve after the round has ended so that flow can reach the round.

Debug-only affordances used so two simulators could play: a password account on the local stack (Sign in with Apple cannot run against a local GoTrue), and the join link opened as `xix://r/CODE` (the app also handles `https://xix.golf/r/CODE`; universal links need the association file served from xix.golf).
