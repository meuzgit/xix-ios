# XIX

A golf scorecard that turns a real round into a game: side games, callouts and stickers that resolve into a results screen. iOS, Supabase, one scoring engine.

Specs live at the repo root: `xix-golf-app-prd-v0.3.md`, `xix-build-doc-1-data-model-and-scoring.md` (schema shape, engine contracts), `xix-build-doc-2-backend-sync-first-screens.md` (Supabase, sync, first screens).

Vocabulary rule for every file, comment and test name: no money, stake, wager or settlement concepts. Say games, callouts, medals, results.

## Layout

| Path | What |
|---|---|
| `XIXScoring/` | The scoring engine, a pure Swift package. Formats, callouts, medals, Rival Points. Fixtures under `Tests/XIXScoringTests/Fixtures`. |
| `XIXScoring/Sources/xix-engine-cli` | RoundInput in on stdin, RoundResult out. Built natively for parity and as WebAssembly for the server. |
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
supabase db reset                           # migrations 0001–0013 plus the Fraserview seed
supabase test db supabase/tests/database    # pgTAP: one file per RLS row, RPC and engine checks
```

All development is local. Nothing here links to or pushes to the shared project; migrations are applied there by hand after each reviewed step, never with `db reset`.

The seed is generated: edit `supabase/scripts/gen_seed.py`, not `supabase/seed.sql`.

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
3. Add a Database Webhook on `xix.engine_queue` insert: POST to `xix-engine`, body `{ "record": { "round_id": … } }`, `Authorization: Bearer <service-role key>`. The function also accepts `{ "round_id": … }` directly.

Auth is Sign in with Apple on the shared Meuz auth. No provider settings change for XIX; profiles are created by `xix.ensure_profile()` after the first sign-in.
