#!/usr/bin/env bash
# Build XIXScoring's engine CLI to WebAssembly and place it where the xix-engine edge function loads it.
# The .wasm is a build product (not committed); run this before `supabase functions serve` or deploy.
set -euo pipefail
# The Wasm SDK belongs to the swift.org toolchain, not Xcode's. A shell that has not sourced a profile
# (a script runner, CI, an agent) will not have swiftly on PATH, and the build fails with a bare
# "unknown SDK" — so add it when it is there.
[ -d "$HOME/.swiftly/bin" ] && PATH="$HOME/.swiftly/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/XIXScoring"
SDK="${XIX_WASM_SDK:-swift-6.3.3-RELEASE_wasm}"
swift build --package-path "$PKG" --scratch-path "$PKG/.build-wasm" --swift-sdk "$SDK" --product xix-engine-cli -c release -Xswiftc -Osize -Xlinker --strip-all
cp "$PKG/.build-wasm/wasm32-unknown-wasip1/release/xix-engine-cli.wasm" "$ROOT/supabase/functions/xix-engine/xix-engine-cli.wasm"
ls -la "$ROOT/supabase/functions/xix-engine/xix-engine-cli.wasm"
