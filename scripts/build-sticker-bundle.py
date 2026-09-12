#!/usr/bin/env python3
"""The sticker bundle: 512px PNGs for the app, generated from the 1024 masters.

Masters live in `masters/stickers/` (1024², RGBA, never in the bundle); the app ships
`XIXUI/Sources/XIXUI/Resources/Stickers/` at 512² so twelve die-cuts cost ~5 MB instead of ~19 MB.
Rive files, when the twelve `.riv` are authored from the same masters, are copied through untouched:
they are already small and the runtime scales them.

    python3 scripts/build-sticker-bundle.py            # write the bundle
    python3 scripts/build-sticker-bundle.py --check    # fail if the bundle is stale (CI)
"""
import argparse
import hashlib
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTERS = ROOT / "masters" / "stickers"
BUNDLE = ROOT / "XIXUI" / "Sources" / "XIXUI" / "Resources" / "Stickers"
SIZE = 512

KEYS = ["BAIL", "CALLED_OUT", "CHOKE", "CLUTCH", "DUCK_IT", "HAHAHA",
        "NO_WITNESSES", "SANDBAGGER", "SIGNED", "SNAKE", "WASTED", "YIKES"]


def render(master: pathlib.Path) -> bytes:
    with Image.open(master) as im:
        im = im.convert("RGBA")
        if im.size != (SIZE, SIZE):
            im = im.resize((SIZE, SIZE), Image.LANCZOS)
        out = BUNDLE / master.name
        im.save(out, format="PNG", optimize=True)
    return out.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when the bundle differs from the masters")
    args = parser.parse_args()

    missing = [k for k in KEYS if not (MASTERS / f"{k}.png").exists()]
    if missing:
        print(f"missing masters: {', '.join(missing)}", file=sys.stderr)
        return 1

    BUNDLE.mkdir(parents=True, exist_ok=True)
    stale = []
    for key in KEYS:
        target = BUNDLE / f"{key}.png"
        before = hashlib.sha256(target.read_bytes()).hexdigest() if target.exists() else None
        after = hashlib.sha256(render(MASTERS / f"{key}.png")).hexdigest()
        if args.check and before != after:
            stale.append(key)
        print(f"  {key}.png  {(BUNDLE / f'{key}.png').stat().st_size // 1024} KB")

    riv = sorted(MASTERS.glob("*.riv"))
    for f in riv:
        (BUNDLE / f.name).write_bytes(f.read_bytes())
    print(f"{len(KEYS)} stills, {len(riv)} rive files → {BUNDLE.relative_to(ROOT)}")

    if stale:
        print(f"bundle is stale for: {', '.join(stale)}. Run scripts/build-sticker-bundle.py.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
