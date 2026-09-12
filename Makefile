# One command per check. Everything runs against the local Supabase stack (never the shared project).

.PHONY: engine-tests pgtap data-tests ui-tests parity wasm models reset

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

wasm:                    ## build the engine to WebAssembly for the edge function
	./scripts/build-engine-wasm.sh

parity:                  ## native vs Wasm on every fixture
	./scripts/engine-parity.sh

models:                  ## regenerate XIXModels row types from the local database
	./scripts/gen-models.sh
