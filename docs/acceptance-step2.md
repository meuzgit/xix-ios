# Build Doc 3 · Step 2 acceptance — stickers on Rive

## 1. All twelve play their slap

`Settings › Sticker lab` (Debug builds only) plays each of the twelve in turn and measures the frame rate with a display link over the slap itself.

Run on the iPhone 16 simulator, 12 September 2026. Every one of the twelve played its slap, and the summary line read **"All twelve played. Slowest: 58.3 fps."**

| Sticker | fps | | Sticker | fps |
|---|---|---|---|---|
| CHOKE | 60.0 | | CALLED_OUT | 58.3 |
| SANDBAGGER | 60.0 | | SIGNED | 58.3 |
| CLUTCH | 60.1 | | YIKES | 58.6 |
| DUCK_IT | 59.9 | | WASTED | 58.5 |
| NO_WITNESSES | 60.2 | | HAHAHA | 58.4 |
| SNAKE | 60.1 | | BAIL | 58.6 |

The first measurement of the session ran at 41 fps, which was the slap rebuilding the image view on every frame. It now animates one stable view with a keyframe animator, and the transform is the render server's work.

## 2. A played sticker on one phone notifies the other

Two simulators, one round, driven by `XIX/UITests/StickerLoopTests.swift` and recorded into `docs/acceptance-step2.mp4`:

Left, Ray: sets a round up with Dave, scores a par for himself and a 7 for Dave, taps Dave's chip, and the tray offers YIKES first because the hole was a blow-up. One tap sends it.

Right, Dave: opens the link, claims his row, goes to hole 1, finds the YIKES on his row, taps it. It plays full screen with the sender named and one line saying he will be told. Closing it leaves the sticker played.

Back on the left, without Ray touching anything: **"Dave opened your YIKES"** in ink on the card.

Both tests passed (70.9 s and 76.9 s). `XIXData/Tests/XIXDataTests/StickerPlayedTests.swift` pins the same path without a screen: the event's text, the hole, who opened it, that a second tap keeps the first stamp, and that the sender cannot open a sticker on the target's behalf.

Watching this run also caught a real bug, now fixed: `send_sticker` mints its own id, so the optimistic row the sender wrote locally never matched the server's and every sticker drew twice on the thrower's card. The queue now swaps the optimistic row for the server's, and the test asserts one sticker on both phones.

## What plays today, and what needs the Rive editor

The twelve `.riv` files are authored in the Rive editor from the 1024 masters, which is design work I cannot do from here. Everything that consumes them is built and wired:

- `RiveStickerRenderer` (in the app) loads `<KEY>.riv` from the bundle, drives the `Sticker` state machine, fires its `play` trigger for the slap and sets `bubble` for CALLED\_OUT's pressed bubbles. It is installed on the environment at launch, so every sticker surface — grid, hole card, tray, callout banner, the full-screen played state — switches over the moment the files exist.
- Any key with no `.riv` keeps its still and plays the same slap from `StickerSlap`, which holds Pass 5's timing exactly. That is what the measurements above ran on.
- `masters/README.md` is the contract for the editor: artboard, state machine name, the `play` trigger, the `bubble` number, and the eight poses with their timings.

So the app is correct before the assets land and correct after, and the acceptance above is honest about which path it measured.

## Notes

- The frame rates are from the iOS Simulator, which renders on the CPU. They are a floor, not a device measurement: a physical phone does this work on the GPU. A true on-device number needs a device I cannot drive from here.
- The sound is one cue on the contact frame. It is muted by the Settings toggle, by quiet mode for the round, and by the phone's silent switch (the session category is `.ambient` and the app never overrides it).
- `pack_key` rides on every sticker; `base` is free and is the only pack in V1. The tray dims and tags anything outside the owned set, and `StickerEntitlements` is a local stub until StoreKit in step 9 — nothing here is proof of purchase.
