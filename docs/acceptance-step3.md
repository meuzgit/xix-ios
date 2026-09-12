# Build Doc 3 · Step 3 acceptance — the callout composer

Three simulators, one round, driven by `XIX/UITests/CalloutLoopTests.swift` and recorded into `docs/acceptance-step3.mp4`. Ray owns the card and throws every callout; Dave and Mo claim their own rows and answer for themselves. Tess is on the card by name and is Ray's partner in the third callout.

## What the video shows

| Hole | Kind | Thrown at | Dave | Mo | What the engine made of it |
|---|---|---|---|---|---|
| 1 | Target, par | Dave and Mo | signs | ducks | Dave made par: he takes it, Mo took no part |
| 2 | Duel | Dave | signs | — | Ray's 4 against Dave's 5: Ray takes it |
| 3 | Partner, with Tess | Dave and Mo | signs | signs | Tess's 3 carries Ray's side |
| 4 | Double, on Skins | Dave and Mo | signs | signs | Both signed, so hole 4 counted twice in Skins |

Then hole 5, where Dave already has a score: the composer says "Dave has already scored this hole." and will not send. The round ends and the results screen carries all four, each with what happened to it.

Recorded 12 September 2026, three simulators side by side, 5 min 21 s. All three tests passed: the owner's in 319 s, the two targets' in 308 s each.

What the last frames carry, read off the results screen:

| Callout | Mark |
|---|---|
| Beat par on 1 | DAVE MADE IT · MO DUCKED |
| Duel on 2 | CALLED IT |
| Partner pick on 3 | CALLED IT · WITH RAY & TESS |
| Double on 4 · Skins | DOUBLED |

The engine also awarded the callout medals that follow from those: Duel Won, and Ducked Nothing for the target who signed every one.

## What the composer refuses, and why twice

Every rule in `CalloutComposerModel` is a rule in `xix.create_callout`. The composer holds them so a player never meets a round trip that was never going to work, and the RPC holds them because the composer is not the only thing that can call it:

| Rule | The composer | The server |
|---|---|---|
| Somebody other than the caller | "Pick who you are calling out." | `a callout needs at least one target other than the caller` |
| A duel is one on one | "A duel is one on one. Pick one player." | `a duel has exactly one target` |
| A Double needs a game | "Pick the game this hole doubles." | `multiplier needs a game in this round` |
| A scored hole is closed | "Dave has already scored this hole." | `a participant has already scored hole 7` |
| Your partner is not your opponent | "Your partner cannot be on the other side." | (the engine drops the partner from the other side) |

`XIXData/Tests/XIXDataTests/CalloutTests.swift` proves the server half: it creates one of each kind through the real RPCs with three signed-in clients, answers per target, and checks the engine's resolutions — including that the server refuses a callout on a scored hole and that the refusal reaches the card as the toast. `XIXUI/Tests/XIXUITests/CalloutComposerTests.swift` pins the composer's copy of the rules, and `CalloutResultsTests.swift` pins the line the results screen prints for each kind.

## Notes

- **The free-tier gate is a stub.** Callouts are a Full feature (PRD 8.6), but nothing is on sale yet, so `XIXFull.isActive` defaults to on and every player can throw one. The contextual gate from Pass 6 6g is built and shown when it is off, and a Debug toggle in Settings switches it so the gate can be seen. Step 9 replaces the flag with StoreKit and a server-side check; nothing here is proof of purchase and the server enforces nothing.
- **`factor` is not sent.** "Double" means the engine's default of 2, so the params carry only the game.
- Ids in `params` go down lowercased, because the engine compares them against the ids Postgres renders.
