#!/usr/bin/env bash
# Engine parity: the native and Wasm builds of xix-engine-cli must produce identical RoundResult JSON
# for every fixture. This is what lets the client trust its local engine against the server's (Doc 2 B.3).
#
# Requires: a Swift 6.3.3 toolchain with the swift-6.3.3-RELEASE_wasm SDK (swift sdk list), node ≥ 20 for WASI.
set -euo pipefail
# The Wasm SDK belongs to the swift.org toolchain, not Xcode's. A shell that has not sourced a profile
# (a script runner, CI, an agent) will not have swiftly on PATH, and the build fails with a bare
# "unknown SDK" — so add it when it is there.
[ -d "$HOME/.swiftly/bin" ] && PATH="$HOME/.swiftly/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/XIXScoring"
SDK="${XIX_WASM_SDK:-swift-6.3.3-RELEASE_wasm}"
FIXTURES="$PKG/Tests/XIXScoringTests/Fixtures"

echo "== native build"
swift build --package-path "$PKG" --product xix-engine-cli -c release >/dev/null
NATIVE="$PKG/.build/release/xix-engine-cli"
echo "== wasm build ($SDK)"
# Separate scratch path: two SDKs in one .build directory confuse the build description.
swift build --package-path "$PKG" --scratch-path "$PKG/.build-wasm" --swift-sdk "$SDK" --product xix-engine-cli -c release -Xswiftc -Osize -Xlinker --strip-all >/dev/null
WASM="$PKG/.build-wasm/wasm32-unknown-wasip1/release/xix-engine-cli.wasm"
echo "   $(du -h "$WASM" | cut -f1) $WASM"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0; n=0
for f in "$FIXTURES"/*.json; do
  name="$(basename "$f" .json)"; n=$((n+1))
  "$NATIVE" < "$f" > "$TMP/$name.native.json"
  node --no-warnings "$ROOT/scripts/run-wasi.mjs" "$WASM" "$f" > "$TMP/$name.wasm.json"
  if python3 "$ROOT/scripts/json-equal.py" "$TMP/$name.native.json" "$TMP/$name.wasm.json"; then
    echo "ok   $name"
  else
    echo "DIFF $name"; fail=$((fail+1))
  fi
done
echo "== $n fixtures, $fail differ"
[ "$fail" -eq 0 ]
