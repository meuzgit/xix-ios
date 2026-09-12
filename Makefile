# One command per check. Everything runs against the local Supabase stack (never the shared project).

.PHONY: engine-tests pgtap data-tests ui-tests parity wasm models reset acceptance app xcconfig app-build

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

app:                     ## generate XIX/XIX.xcodeproj from XIX/project.yml (xcodegen)
	cd XIX && xcodegen generate

xcconfig:                ## write XIX/Config/Shared.xcconfig from the linked project's anon key (never printed)
	./scripts/gen-xcconfig.sh

app-build: app           ## build the app for the simulator (Debug → local stack)
	xcodebuild -project XIX/XIX.xcodeproj -scheme XIX -configuration Debug -destination 'generic/platform=iOS Simulator' build | grep -E "error:|BUILD"
