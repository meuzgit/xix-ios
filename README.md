# XIX

A golf scorecard that turns a real round into a game: side games, callouts and stickers that resolve into a results screen. iOS, Supabase, one scoring engine.

Specs live at the repo root: `xix-golf-app-prd-v0.3.md`, `xix-build-doc-1-data-model-and-scoring.md` (schema shape, engine contracts), `xix-build-doc-2-backend-sync-first-screens.md` (Supabase, sync, first screens).

Vocabulary rule for every file, comment and test name: no money, stake, wager or settlement concepts. Say games, callouts, medals, results.

## Layout

| Path | What |
|---|---|
| `XIXScoring/` | The scoring engine, a pure Swift package. Formats, callouts, medals, Rival Points. Fixtures under `Tests/XIXScoringTests/Fixtures`. |
| `XIXScoring/Sources/xix-engine-cli` | RoundInput in on stdin, RoundResult out. Built natively for parity and as WebAssembly for the server. |
| `XIXModels/` | Row types mirroring the `xix` tables, generated from the local database (`scripts/gen-models.sh`) and hand-wrapped. |
| `XIXData/` | Supabase client, Sign in with Apple, repositories, `RoundSession` (one Realtime channel per round, last-write-wins per cell, merge notices), GRDB local store and offline queue. No UI. |
| `XIXUI/` | Design tokens from Pass 5, the base sticker pack, `ScorecardRenderer` (one view tree for the screen and for export), the grid screen and the hole card bound to `RoundSession`, with pixel snapshots. |
| `XIX/` | The app target (Build Doc 3): `project.yml` for xcodegen, the screens that compose the packages (Home, setup, round, results, join, sign-in), and the two-device UI tests. |
| `web/` | The static no-app landing page for join links and the universal-link association file. |
| `masters/` | The 1024² sticker masters and the `.riv` authoring contract. Never shipped: the app bundles 512² versions built by `scripts/build-sticker-bundle.py`. |
| `supabase/` | Migrations, seed, pgTAP tests, the `xix-engine` edge function. |
| `scripts/` | Engine build and parity checks. |
| `fraserview_2026-09-09.json` | The reference round every design pass uses; source of the seed. |

## Engine

```bash
cd XIXScoring && swift test
```

Every fixture's `expected` block was written by hand before its format. The harness diffs each field and reports path, expected and actual.

## Local Supabase

Needs Docker (Colima works: `brew install colima docker && colima start`) and the Supabase CLI.

```bash
supabase start                              # local stack on Postgres 17
supabase db reset                           # migrations plus the Fraserview seed and a dummy Vault secret for the local webhook
supabase test db supabase/tests/database    # pgTAP: one file per RLS row, RPC and engine checks
```

All development is local. Nothing here links to or pushes to the shared project; migrations are applied there by hand after each reviewed step, never with `db reset`.

The seed is generated: edit `supabase/scripts/gen_seed.py`, not `supabase/seed.sql`.

## Data layer

```bash
make data-tests                              # db reset, then the XIXData integration tests against the local stack
```

Testing note: the integration tests sign the seeded users in with a password the service role sets on the user just before (`LocalSupabase.signIn`). Sign in with Apple cannot run in a test; minted JWTs are refused by GoTrue for lacking a session row; magic links set `recovery_sent_at`, which supabase-swift's session storage migrations mishandle. The session a password yields is the same kind any provider yields. After a migration, regenerate the row types with `make models`.

`make` lists every target: `engine-tests`, `pgtap`, `data-tests`, `ui-tests`, `acceptance`, `wasm`, `parity`, `models`. The acceptance record for each tag lives in `docs/`.

## UI

```bash
make ui-tests                                # tokens, sticker pack, scorecard snapshots (macOS)
RECORD_SNAPSHOTS=1 make ui-tests             # re-record after an intended visual change, then run again to compare
```

Snapshots live in `XIXUI/Tests/XIXUITests/__Snapshots__` and are compared pixel-wise with a small tolerance; a failing comparison writes `<name>.failed.png` beside the reference. They are recorded on macOS and expect the same text rendering.

## App

```bash
brew install xcodegen
make app                                     # XIX/XIX.xcodeproj from XIX/project.yml (not committed)
make xcconfig                                # XIX/Config/Shared.xcconfig from the CLI's anon key (not committed)
open XIX/XIX.xcodeproj
```

Debug builds talk to the local stack (`supabase start`, plus `supabase functions serve --no-verify-jwt` so the local engine webhook has somewhere to post); Release builds talk to the shared project. Settings ("···" on Home) carries a Debug-only backend switch, and the sign-in sheet in Debug builds offers a password account on the local stack, since Sign in with Apple cannot run against a local GoTrue. The bundle id is `golf.xix.app`; it must match the Apple provider's client id on the shared project.

The step 1 acceptance (two phones, one round, a guest joining by link mid-round) is a pair of UI tests in `XIX/UITests` driven on two booted simulators and recorded:

```bash
XIX_SIM_A=<udid> XIX_SIM_B=<udid> ./scripts/acceptance-video.sh   # writes docs/acceptance-step1.mp4
```

The same script records the later steps' acceptances, taking the tests to run and a third phone when one is needed:

```bash
XIX_SIM_A=<a> XIX_SIM_B=<b> XIX_SIM_C=<c> \
  XIX_TESTS_A=XIXUITests/CalloutLoopTests/testOwnerThrowsAllFourKinds \
  XIX_TESTS_B=XIXUITests/CalloutLoopTests/testDaveAnswersAsATarget \
  XIX_TESTS_C=XIXUITests/CalloutLoopTests/testMoDucksThenSigns \
  XIX_VIDEO_OUT=docs/acceptance-step3.mp4 ./scripts/acceptance-video.sh
```

A run needs `supabase functions serve --no-verify-jwt` alongside the local stack, so the engine webhook has somewhere to post. If a recording ever fails to start with "Host recording is already in progress", a simulator was left holding a video session: reboot it.

## Stickers

The twelve die-cuts are bundled at 512² (3.5 MB) and generated from the 1024 masters:

```bash
python3 scripts/build-sticker-bundle.py          # masters/stickers → XIXUI's bundle
python3 scripts/build-sticker-bundle.py --check  # fail when the bundle is stale
```

A sticker draws through `\.stickerRenderer`. XIXUI itself only ever draws the still PNG, which is what the snapshots and the exported card use; the app installs `RiveStickerRenderer`, so any key with a `<KEY>.riv` in the bundle plays its Rive state machine instead — pinned on the card, the slap when it is opened, and the pressed bubbles on CALLED\_OUT. Until those files are authored, the same slap plays from `StickerSlap`, which holds Pass 5's timing (peel in 1.4× / −34°, contact on frame 3 with the cue, squash 0.82 × 1.18, rebound 1.08 × 0.92, settled at 620 ms). `masters/README.md` is the contract for the editor work.

Tapping a sticker somebody threw at you plays it full screen and marks it played; the sender's phone says so in ink ("Dave opened your YIKES"). The sound is one cue on the contact frame, muted by the Settings toggle, by quiet mode for the round, and by the phone's silent switch.

## Callouts

"Call someone out" on the hole card opens the composer: the kind (Target, Duel, Partner, Double), who it is aimed at, and the one extra each kind needs — a goal, a partner, or the game that doubles. The CALLED OUT banner previews itself as you choose, because that banner is what the others will see, and their two drawn bubbles are the controls that answer it.

`CalloutComposerModel` holds the same rules as `xix.create_callout`, so a player never meets a round trip that was never going to work: somebody other than the caller, one target for a duel, a game for a Double, a partner who is not also an opponent, and a hole nobody in the callout has scored yet. The server holds them too, and a refusal it raises reaches the card as the toast.

Callouts are a Full feature. Nothing is on sale yet, so `XIXFull.isActive` defaults to on; the contextual gate from Pass 6 6g is built and a Debug toggle in Settings shows it. Step 9 replaces the flag with StoreKit and a server-side check.

## Engine toolchain (WebAssembly)

The server runs the same engine compiled to WebAssembly. That needs the swift.org toolchain, not Xcode's, and a Wasm SDK of exactly the same version.

```bash
# swiftly from https://www.swift.org/install (user-level, no admin)
swiftly install 6.3.3 --use
swift sdk install https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7
swift sdk list                              # swift-6.3.3-RELEASE_wasm
```

When the toolchain version changes, the SDK, `scripts/*.sh` and `.github/workflows/engine-parity.yml` change together.

```bash
./scripts/build-engine-wasm.sh              # builds the module and places it in supabase/functions/xix-engine/
./scripts/engine-parity.sh                  # native vs Wasm, every fixture, identical JSON or fail
```

The `.wasm` is a build product and is not committed. Parity runs in GitHub Actions on every engine change; that check is what lets the app trust its local engine against the server's.

## Running the engine locally end to end

```bash
./scripts/build-engine-wasm.sh
supabase functions serve --no-verify-jwt
curl -X POST http://127.0.0.1:54321/functions/v1/xix-engine -H 'Content-Type: application/json' \
  -d '{"record":{"round_id":"66666666-6666-4666-8666-666666666666"}}'
python3 supabase/scripts/verify_engine_result.py   # results.payload must equal the fixture's expected block
```

## Shared project (applied by hand after each reviewed step)

1. Expose the `xix` schema in the API settings (Data API → exposed schemas), matching `[api] schemas` in `supabase/config.toml`.
2. Deploy the function with the module built first: `./scripts/build-engine-wasm.sh && supabase functions deploy xix-engine`. The `[functions.xix-engine]` entry in `config.toml` declares the `.wasm` as a static file and disables JWT verification (the webhook carries the service-role key).
3. The engine webhook is migration 0018: `xix.notify_engine_webhook()` posts every `xix.engine_queue` row to the function through pg_net, with the bearer key read from Vault. Store it once per project: `select vault.create_secret('<service-role key>', 'xix_service_role_key')` (and optionally `xix_engine_url` to override the function URL). Locally `supabase/seeds/local_vault.sql` seeds a dummy key and points the URL at `supabase functions serve`.
4. `make xcconfig` for the app's Release configuration; the anon key never leaves the machine.

Auth is the shared Meuz auth with three ways in: Sign in with Apple, Google (the native SDK's id token, exchanged like Apple's), and an email one-time code (`signInWithOTP` + `verifyOTP`; 8 digits on the shared project, 6 locally). Provider and linking settings are dashboard work, not the repo's. Profiles are created by `xix.ensure_profile()` after the first sign-in. Settings › "Add another sign-in method" attaches Apple or Google through `linkIdentity` with their id token, and an email address through the email-change code. Locally the code mails go to Mailpit on port 54324 with the templates in `supabase/templates/`; `AuthOTPTests` reads the code back from there.
