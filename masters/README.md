# Sticker masters

The twelve die-cuts at 1024², as delivered. Nothing here ships: `scripts/build-sticker-bundle.py` writes the 512² versions the app bundles into `XIXUI/Sources/XIXUI/Resources/Stickers/`.

```bash
python3 scripts/build-sticker-bundle.py          # write the bundle from these masters
python3 scripts/build-sticker-bundle.py --check  # fail if the bundle is stale
```

## The `.riv` files (Rive editor work)

Build Doc 3 step 2 animates each sticker with a Rive state machine. The app is already wired for them: drop `<KEY>.riv` beside its master here, run the script, and every sticker surface — the grid, the hole card, the tray, the callout banner and the full-screen played state — switches from the still to the state machine with no code change. A key with no `.riv` keeps its still, so the app is correct either way.

Each file must satisfy this contract, which `XIX/Sources/Stickers/RiveStickerRenderer.swift` drives:

| | |
|---|---|
| Artboard | any (the default artboard is used) |
| State machine | `Sticker` |
| Trigger `play` | plays the slap once, then rests in the pinned pose |
| Number `bubble` | `CALLED_OUT.riv` only: 0 none, 1 SIGN IT held, 2 DUCK IT held |

**The slap**, from Pass 5 and mirrored exactly in `XIXUI/Sources/XIXUI/Tokens/StickerSlap.swift`, which is what plays until the `.riv` files exist:

| At | Pose |
|---|---|
| 0 ms | scale 1.40, −34°, transparent |
| 16 ms | scale 1.34, −26°, opaque |
| 50 ms (frame 3) | scale 1.00, 0° — the contact, where the sound cue fires |
| 110 ms | squash 0.82 × 1.18 |
| 200 ms | rebound 1.08 × 0.92 |
| 300 ms | 0.97 × 1.03 |
| 420 ms | 1.01 × 0.99 |
| 620 ms | flat, settled |

The pinned state is the still pose: no idle motion, no loop. A sticker on the card does not move until somebody opens it.

`CALLED_OUT.riv` additionally carries the pressed state the still draws today: the held bubble darkens and the whole die-cut goes to 0.96. The hit areas stay where they are — they are drawn by `CalloutBanner`, not by Rive, so the two bubbles keep their ≥44 pt targets at (0.27, 0.74) and (0.75, 0.74).
