# One command per check. Everything runs against the local Supabase stack (never the shared project).

.PHONY: engine-tests pgtap data-tests ui-tests parity wasm models reset acceptance

engine-tests:            ## XIXScoring unit tests and fixtures
	swift test --package-path XIXScoring

reset:                   ## migrations + Fraserview seed on the local stack
	supabase db reset

pgtap: reset             ## one pgTAP file per RLS row, RPC and engine check
	supabase test db supabase/tests/database

data-tests: reset        ## XIXData integration tests against the local stack
	swift test --package-path XIXData

ui-tests:                ## XIXUI tokens, sticker pack and scorecard snapshots
	swift test --package-path XIXUI

acceptance: reset wasm   ## D.5 item 3: the Fraserview round by hand through the session vs the server's results.payload
	@(supabase functions serve --no-verify-jwt > /tmp/xix-functions.log 2>&1 & echo $$! > /tmp/xix-functions.pid); sleep 15
	XIX_ACCEPTANCE=1 swift test --package-path XIXData --filter AcceptanceTests; status=$$?; kill $$(cat /tmp/xix-functions.pid) 2>/dev/null; exit $$status

wasm:                    ## build the engine to WebAssembly for the edge function
	./scripts/build-engine-wasm.sh

parity:                  ## native vs Wasm on every fixture
	./scripts/engine-parity.sh

models:                  ## regenerate XIXModels row types from the local database
	./scripts/gen-models.sh
