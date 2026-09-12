# Acceptance — v0.3.0-app

Build Doc 2 D.5, recorded 11 September 2026 against the local Supabase stack (Postgres 17, Realtime, Auth, PostgREST, edge runtime) on this Mac. Every check is a test in the repo and can be re-run with the commands shown. Nothing here touched the shared project.

## Summary

| D.5 item | Result | Where |
|---|---|---|
| 1. Two devices on the same round see each other's scores within 1 s | Pass, 0.135 s observed | `XIXData` `SyncTests.testTwoSessionsSeeEachOthersScoresWithinASecond` |
| 2. Airplane mode for three holes, then reconnect: all scores present, correct LWW, one merge notice per replaced displayed cell | Pass | `SyncTests.testOfflineThreeHolesThenReconnect` |
| 3. Server `results.payload` equals the local `RoundResult` for the Fraserview round entered by hand | Pass, and equal to the fixture's expected block | `AcceptanceTests.testFraserviewEnteredByHandMatchesServerAndFixture` (`make acceptance`) |
| 4. Guest join via link → claim row → score own row; owner can still edit it | Pass | `GuestJoinTests.testGuestJoinsClaimsScoresAndOwnerCanEdit` |
| 5. Existing MMM user signs into XIX with the same Apple ID → same auth user, no linking | Pass | `AuthTests.testExistingAuthUserIsTheSameUserInXIXAndProfileIsCreatedOnce` |

Supporting suites at the tag: engine 114 tests and 24 fixtures green; native vs Wasm parity 24 of 24 identical; pgTAP 159 assertions across 17 files; XIXData 5 tests (one skipped unless `XIX_ACCEPTANCE=1`); XIXUI 18 tests with 13 pixel snapshots.

## What was run and what was observed

### 1. Two sessions see each other's scores

Run: `make data-tests`. Two `RoundSession`s in one process, signed in as Ray and Dave, on a fresh live round Ray created and Dave claimed a row in, each with its own local store and Realtime channel.

Observed: Ray's hole 1 appeared in Dave's session 0.135 s after Ray's save; Dave's hole 1 appeared in Ray's session within the 5 s wait; both local engines then reported identical status and per-player totals. No merge notice was raised, since new cells never do.

Caveat: two sessions in one process on the local stack, not two phones on Wi-Fi. The Realtime path, RLS and the per-cell merge are the same; radio latency is not measured here.

### 2. Offline for three holes, then reconnect

Run: `make data-tests`. Dave's session goes offline (connectivity override: the Realtime channel is left and the outbox pauses), Ray plays three holes and, as owner, enters a 9 on Dave's hole 2. Dave then enters his own holes 1–3 offline, with a later stamp on hole 2. Dave reconnects.

Observed: nothing arrived while Dave was offline; his three writes queued (`pendingWrites == 3`) and rendered from the local store; on reconnect the session refetched the round under last-write-wins, rejoined the channel and drained the queue in order. Both stores ended with the same six cells. Dave's later stamp won hole 2, replacing Ray's displayed 9 with 6: exactly one merge notice on Ray, "Dave changed hole 2", none on Dave (own row and new cells raise none).

Caveat: airplane mode is simulated by the session's connectivity override rather than the radio; the code path on reconnect (refetch, rejoin, drain) is the one the app runs from `NWPathMonitor`.

### 3. Server result equals the device's result for the Fraserview round entered by hand

Run: `make acceptance` (resets the stack, builds the Wasm module from current sources, serves the edge function, runs the test). A scripted session drives the same call the hole card's Save button makes, `RoundSession.enterScore`, for all 72 scores of `fraserview_2026-09-09.json` in hole order as Ray, including Mo's pick-up on 13. Ray creates Fraserview with par and stroke index and the three games via `set_games`; Dave claims his row; the two target callouts are raised by Ray before holes 8 and 12 and Dave signs the first and ducks the second, as in the fixture. Ray ends the round, the edge function runs the engine, and the test reads `results.payload` back.

Observed: 72 scores entered and acknowledged in 0.4 s; the round's local `RoundResult` is `.complete`; the server payload decodes to a `RoundResult` equal to the local one field for field (`XCTAssertEqual`); after mapping this round's ids back to the fixture's, the payload matches the fixture's expected block under the harness rules (zero mismatches); five medals stored on the server, the local medals of the two claimed players: `nassau_front`, `nassau_18`, `skins_two`, `skins_four`, `callout_called_it` for Ray. Mo and Tess are guests and receive theirs on claiming (`claim_row` enqueues a recompute).

Three defects this check found and fixed before it passed: a nil `strokes` on a pick-up was dropped from the RPC body so PostgREST could not match `enter_score`; games written in one `set_games` call shared a `created_at`, so the server ordered them by id and medal order differed from the device's (migration 0017 adds `games.position`); the Wasm module in the function directory predated the engine's compact-standing field (the acceptance target now rebuilds it, and nested match details decode the field tolerantly).

Caveat: a scripted session rather than a simulator UI test; the input path from the pad's Save to the server is identical from `enterScore` down.

### 4. Guest join, claim, score, owner edits

Run: `make data-tests`. A new auth user (as a person tapping the link would be after Sign in with Apple) calls `join_round` with the code, reads the join screen from `joinable_rows` (course, owner, every row, which are claimable), claims the guest row, and enters hole 1 through their session.

Observed: the join screen listed Ray and Guest with only Guest claimable; the claim set `profile_id`; the guest's 5 appeared in Ray's session; Ray's edit to 6 appeared in the guest's session; the guest's attempt to write Ray's row was refused by the server, the local cell reverted, and one rejection was reported.

### 5. Same auth user across apps

Run: `make data-tests`. An auth user created ahead of time with no XIX profile (as an MMM user is) signs in.

Observed: `isSignedIn` was false on first launch; after sign-in `ensure_profile` created the profile with the same id as the pre-existing auth user and the display name from the credential metadata; a second call changed nothing (one row); sign-out cleared the session.

Caveat: sessions in tests come from a password the service role sets just before sign-in, since Sign in with Apple cannot run headless. The session is the same kind GoTrue issues for any provider, and the same-id property is what the check is about. Insider status is read from MMM's schema in Build Doc 3.

## Not covered at this tag

Two physical devices and real airplane mode (items 1 and 2 above are exercised in-process); the simulator UI path for item 3; the shared project itself (migrations 0001–0017, the `xix` API schema, the Realtime publication, the function deploy and the webhook are applied by hand after review).
