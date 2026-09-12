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
MODULE="$ROOT/supabase/functions/xix-engine/xix-engine-cli.wasm"
cp "$PKG/.build-wasm/wasm32-unknown-wasip1/release/xix-engine-cli.wasm" "$MODULE"

# Stamp the module's hash into the function. The CLI decides whether to upload by looking at the
# function's source, not at its static files, so without this a rebuilt engine deploys as "no change
# found" and the project keeps running the old one.
SHA="$(shasum -a 256 "$MODULE" | cut -d" " -f1)"
INDEX="$ROOT/supabase/functions/xix-engine/index.ts"
python3 - "$INDEX" "$SHA" <<'PY'
import re, sys
path, sha = sys.argv[1], sys.argv[2]
src = open(path).read()
new = re.sub(r'const ENGINE_MODULE_SHA = "[0-9a-f]{64}";', f'const ENGINE_MODULE_SHA = "{sha}";', src)
if new == src and f'"{sha}"' not in src:
    raise SystemExit("could not stamp ENGINE_MODULE_SHA into index.ts")
open(path, "w").write(new)
PY
echo "   module $SHA"
ls -la "$MODULE"
