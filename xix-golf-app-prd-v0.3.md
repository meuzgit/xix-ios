# XIX — Golf App
## Product Requirements Document, v0.3

**Status:** Build-ready. Hero flows locked (Pass 5); remaining flows locked (Pass 6); Pass 7 covers a small remainder (see §16)  
**Date:** 12 September 2026  
**Platform:** iOS only (native SwiftUI) + Apple Watch companion  
**Name:** *XIX* — pending trademark clearance  
**Related products:** Standalone app. Conduits to My Main Man (MMM) for "Where to now?" and to On My Money (OM) for scorecard recognition.  
**Design reference:** Claude Design files *XIX Pass 5 — Stickers Are Speech* and *XIX Pass 6 — The Rest of the App* (locked). Sticker assets: 12 die-cut PNGs.

**Changes from v0.2:** Pass 6 flows locked and specified (§8.16–8.22); Level displays as a number (1–10); auth is Sign in with Apple only on the shared Meuz auth (no anonymous tier); MMM gate copy must mirror MMM's actual allowance rule; Picked-up rule, MMM feed source and standalone XIX Full subscription confirmed.

**Changes from v0.1:** Where to now moved out of XIX Full and onto MMM's own gating; visual system locked (broadcast base, riso sticker family, riso medal patches); two-layer card (grid + hole card) replaces the single grid; stickers defined as player speech only; callout banner is the CALLED OUT die-cut; "Where to now?" is the MMM feed reproduced as built; tiers simplified to Free / Full; stake labels removed entirely; score pad gains 1, 10+ and Picked up; Apple Watch and Supabase confirmed.

---

## 1. One-line definition

A golf scorecard that turns a real round into a game — side games, mid-round callouts and trash-talk stickers that resolve into a video-game-style results screen — and then tells you where to go next.

## 2. Purpose

**Purpose 1 — make golf fun to play, whatever your level.**
The app is the digital layer on a real-life game. Golfers who aren't good get something to win; seasoned golfers get their usual side games with a better scoreboard. The round ends the way a match in a video game ends: a results screen with medals and highlights. The app never states what any result *means* — that is left entirely to the players.

**Purpose 2 — where next.**
After the results screen, "Where to now?" — the MMM feed of places to eat and drink near the course. This extends the golf day past the 18th and puts MMM in front of every golfer who finishes a round. It is a promotion surface for MMM as much as a feature of this app.

## 3. Goals and non-goals

**Goals (V1)**
- Be the scorecard a regular group (two to four players) chooses over Hole19/18Birdies because the round is more fun in it.
- Every round produces a screenshot-worthy artifact (the scorecard) and a results screen people want to share.
- Zero legal exposure: no wagering, no money, no obligations recorded.
- Drive installs of MMM from the "Where to now?" surface.

**Non-goals (V1)**
- GPS, yardages, shot tracking, swing analysis, handicap indexing.
- Tee-time booking.
- Remote/cross-course matches or challenges.
- In-app chat or free-text messaging.
- Any form of payment, settlement, IOU, points-as-currency, stake labels or stake tracking.
- Course or venue partnerships.
- Android.

## 4. Users

| Persona | What they want | What wins them |
|---|---|---|
| **The regular group** (serious, plays weekly, already runs Nassau/skins) | Correct maths, no arguments, keep their GPS app | Games auto-tabulated, synced card, callouts, stickers |
| **The casual golfer** (finding the fun, may shoot 100+, may not keep score) | Something to win that isn't "lowest score" | Casual-first games, callouts, medals, no handicap asked, no "+16" |
| **The golf-trip group** (post-V1) — 6–12 friends on a multi-day golf trip | Team competition across several rounds, and memories | Trip formats (roadmap), the exported card |

## 5. Product principles

1. **Phone away, golf on.** Nothing requires attention between shots. Setup < 60 seconds; per-hole entry 2 taps; everything else is optional or end-of-round.
2. **Strokes are the only input.** Every game resolves from hole scores.
3. **Results, not debts.** The app shows what happened; it never says what anyone owes.
4. **The scorecard is the product.** One object carries scores, games, callouts, stickers and medals, and that object is what gets exported and shared.
5. **Stickers are speech; ink is record.** A sticker appears only because a player threw it. The app itself only ever draws ink: the printed-card marks and the callout mark.
6. **No chat.** In-match communication is stickers only.
7. **In-person only.** Games, callouts and stickers exist inside a group on the same course, same day. Remote is passive rankings.

## 6. Core loop

```
Setup (owner) → Play (hole card: score, callouts, stickers; grid as overview)
   → Finish (confirm scores or snap paper card)
   → Results screen (games, callouts, medals, highlights)
   → Where to now? (MMM feed)
   → Export card / results → group chat → invite loop
```

## 7. Visual system (locked)

**Base — Broadcast.** Deep forest green header, white sheet, tracked caps, right-aligned numbers, hairline rules. Reads as a TV leaderboard: credible to a serious golfer, quiet enough that stickers disrupt it. Own green and own wordmark; no tournament references.

**Ink.** Printed-card marks drawn by the app: circle = birdie or better, square = bogey, filled square = double or worse. The live-callout mark on a hole's column header. Thin green line only; never a die-cut.

**Family A — Stickers.** One-colour riso screenprint: forest green ink on cream, chunky bubble/beveled headline plus one line-art object as a visual pun, cream die-cut edge, occasional single accent (safety orange / red). Placed flat (0–4°), never scattered. Every sticker carries a sender chip welded to its edge.

**Family B — Medals.** Five patch silhouettes (shield, oval, rounded square, pennant, circle), same riso press: forest on cream, one accent each, game name in the patch, context line beside it. Contained shapes, never headline-plus-object.

**MMM yellow** appears in exactly one place: the "Open in My Main Man" handoff button.

## 8. Feature specification

### 8.1 Tiers

| Tier | Contents | Pricing |
|---|---|---|
| **Free** | Scorecard and sync, hole card, personal record, global and crew rankings, base sticker pack (12), **two games per round**, export | Free forever |
| **XIX Full** | Full games library and unlimited games per round, **callouts** | Subscription ≈ CAD 40/yr; monthly option |
| **Where to now?** | The MMM feed inside XIX | Gated by **MMM**, not XIX: MMM's free allowance applies, then MMM Insider is required (see §8.10) |

Sticker packs beyond the base are consumable IAP. XIX Full locked-state copy: *"Callouts and every game"* / *"Scoring and stickers stay free."* Where to now is product placement for MMM inside XIX and carries MMM's own entitlement: it is not part of XIX Full.

### 8.2 Round setup (owner)

- Owner creates the round: course (search, or type any name — no database match required), tee (optional), players.
- Players are added by name; existing users or guests with no account. Owner can score any row; players who join score their own.
- Owner activates games; each player toggles which games they are in. Mixed combinations allowed (Nassau A–B, Skins all four, Stableford C–D).
- Par-dependent games (Stableford, Bogey Golf, Fewest Blow-Ups, Most Pars, the "beat par" callout) are greyed with a one-tap "add par" prompt when par is unknown; stroke-only games are always available.
- "Same as last time" restores the previous round's players and games in one tap.
- A join link/QR goes to the group chat. Joining from the link drops the player straight into the live card.

### 8.3 The two-layer card

**Layer 1 — the grid (overview).**
- Two nine-hole blocks, par row, OUT/IN/TOT, printed-card marks. Each player edits only their own row; owner can edit any row.
- Live leaderboard strip on top. **Default mode is the active game** (skins held, Nassau up/down, Stableford points); Gross-to-par is a pill the user can switch to. The strip never shows "+16" next to a casual player by default.
- Stickers on the grid are **24–28pt**, anchored top-right of the cell, overhanging into the row gap, covering at most a third of the digit. One sticker per cell (top sticker plus a "×n" tab for stacks). Totals columns never carry stickers.
- A live callout is marked on its hole's column header (ink).
- Tapping any cell or hole number opens that hole's card.

**Layer 2 — the hole card (play surface).**
- One hole per screen; opens on the current hole during play; swipe left/right between holes; hole selector strip at the bottom. Sheet moves, green chrome stays.
- Header: hole number, par, yards/stroke index when known.
- **In-play strip**: one line naming what is live on this hole ("Skins · carry 1 · Nassau back nine").
- Player rows: avatar chip, name, **game standing** under the name ("Skins 2 · Nassau 1 up") — never gross-to-par unless the leaderboard is in Gross mode — and a large score box.
- Stickers pinned at 60–72pt, anchored to the score side of the row, overlapping freely across rows but **never over names or score digits**. The game-standing line is the sacrificial element.
- The callout banner (§8.6), the nudge line and the tray (§8.7) live here.
- After a hole resolves a game event, one line of ink under the rows states it ("Skin to Tess. Carry cleared.").
- White edge to edge. The tray and the number pad rise as panels; nothing behind them dims.

### 8.4 Score input

1. **Hole card pad (primary):** tap your row, tap the number. Keys **1–9**, then **10+** and **Picked up** on their own row; the par key is largest. Saving the last score on a hole closes the pad and fires any event nudge. The grid cell fills behind the scenes.
2. **Apple Watch:** own row only; Digital Crown to change, tap to confirm.
3. **Snap the card** (end of round): frame overlay; tap to assign rows to players; recognition pre-fills the grid and reads par; **confirmation grid is mandatory** (every cell editable, low-confidence cells highlighted, per-player totals checked against the written totals); low confidence falls back to a blank grid pre-filled with par; photo stored with the round. Engine: OM's recognition pipeline, adapted.
4. **Screenshot import:** the same recogniser on a scorecard screenshot from another app.

**Picked up** counts as a defined maximum for tabulation: **double par** in stroke formats (and for gross totals), **zero points** in Stableford-style formats. Shown on the card as "X" with the filled-square mark.

### 8.5 Games library (V1)

All games resolve from hole scores. **Anywhere** = also valid as a passive ranking metric. **Par** = requires par.

**Classic:** Match Play; Stroke Play (gross/net); Stableford (Par, Anywhere); Nassau (front/back/18); Skins (carryover, optional validation); Best Ball / Four-Ball; Scramble; Shamble; Alternate Shot; Chapman.

**Group:** Vegas; Nines (9 Points); Sixes (Round Robin); Quota/Chicago (Par, Anywhere, needs Level); Rabbit; Defender.

**Casual-first (no handicap):** Fewest Blow-Ups (Par, Anywhere); Beat Your Average (Anywhere, needs 3 rounds); Bogey Golf (Par, Anywhere); Most Pars (Par, Anywhere); First to Five (Par); Worst Hole (group votes a nickname).

**Passive ranking formats (Free, no group):** Stableford vs Level; Birdie Race (monthly); Most Pars; Rounds Played.

**Not in V1 (need non-stroke input):** Wolf (full-round), Banker, Hammer, Press, String, Bingo Bango Bongo, Snake, junk, lost-ball counts, honour games. Their fun is recovered through callouts and stickers.

### 8.6 Callouts (XIX Full)

A player-initiated, single-hole mini-game inside the round. All resolve from strokes.

**Primitives:** Target ("Beat par on 8"; solo or crew; nobody hits it → caller wins) · Duel (lowest score on one hole, head-to-head) · Partner pick (one-hole Wolf: caller names a partner or goes alone; best ball per side) · Multiplier (doubles the hole's value in an active base game; other side accepts or declines).

**Rules**
- Must be accepted before the hole is played; auto-expires when any score lands on that hole. **No acceptance, no game.**
- The banner is the **CALLED OUT die-cut** placed directly on the white sheet of the hole card — no container. Its two drawn bubbles are the controls: **SIGN IT** (accept) and **DUCK IT** (decline), with ≥44pt tap targets and a pressed state (bubble darkens, sticker squashes 0.96). One small tracked-caps line carries the detail ("BEAT PAR ON 12 · RAY → DAVE · EXPIRES ON SCORE"). The challenger's chip is welded to the banner's edge.
- Accept → the acceptor's SIGNED sticker pins to the hole. Decline → the decliner's DUCK IT sticker pins to the hole. These are player-sent stickers, never system placements.
- Callout outcomes feed their own medal set and never alter base-game results.
- No stake labels, no forfeit text, anywhere.

### 8.7 Stickers

- **Speech only.** A sticker appears on the card only because a player tapped it. The app never places one for performance; if nobody reacts, the hole stays clean.
- **Attributed.** Every pinned sticker carries a ~16pt sender chip welded to its die-cut edge, on the grid, the hole card and the export.
- **Nudge, not tray.** After a scorecard event, the hole card shows one quiet line — "Dave made 7. React?" — with a Stickers button. The tray opens only on tap, as a panel on white, suggesting the contextual stickers first and the whole set after.
- **Rate limits:** 3 per hole per player; per-round quiet mode mutes incoming.
- **Two states per sticker:** pinned (static) and played (full-screen overlay when the recipient taps; sender notified). The slap: peel in off-screen at ~1.4× and −34°, smack at frame 3 with one sound cue, squash 0.82 × 1.18, rebound 1.08 × 0.92, settle flat. ~620 ms. Owned by the Rive state machine.
- **Base pack (free, 12):** CHOKE · SANDBAGGER · CLUTCH · DUCK IT · NO WITNESSES · SNAKE · CALLED OUT · SIGNED · YIKES · WASTED · HAHAHA · BAIL. CALLED OUT, SIGNED and DUCK IT are also the callout UI.
- **Contextual suggestions (ordering only):** triple or worse → YIKES, WASTED, HAHAHA; birdie or better → CLUTCH; callout ducked → DUCK IT, HAHAHA; suspicious Level → SANDBAGGER; three-putt/water when noted → SNAKE / BAIL; nobody saw it → NO WITNESSES.
- **Packs:** paid packs (seasonal, trip), earned stickers unlocked by medals, house characters. Crew-uploaded packs post-V1.

### 8.8 Level

- After 3 rounds the app computes a rolling average vs par and expresses it as a **Level (1–10), shown as a number** ("Level 5"; "Auto · 5" in Settings). It appears next to names on rankings. Serious golfers may enter a real index, which overrides.
- Net games and Quota require a Level; until it exists they are greyed with a reason. Course rating/slope out of V1; net play is same-course only.

### 8.9 Results screen

- Post-match recap: headline score with the games line under it ("78 · 2 skins · 1 up front"); **medals first**, large, popping in one by one; per-game outcomes; callouts won / lost / ducked shown with the SIGNED and DUCK IT marks; stickers received; highlights (best hole, worst hole, streaks). Rival Points sit small on the sticker line.
- Medals are named objects with context ("Nassau Front Nine — vs. Dave · Fraserview · 9 Sep 2026") and accumulate in a per-rivalry cabinet.
- **Rival Points:** awarded for wins, weighted by game and opponent Level; earned only, never purchasable; used solely for rankings.
- Never displays debts, stakes or "owes".
- Exportable as an image via the shared renderer.

### 8.10 Where to now? (MMM-gated)

- Follows the results screen. **The MMM feed reproduced exactly as built** — not reinterpreted: MMM header ("[Course area] through [Source]" with sort chevrons), MMM pill row showing **Eat** and **Drink** only, hero card (name, city, action icons, watercolour, drive-time · distance, OPEN), two-column grid cards with status dots and status lines, MMM's own empty-state tiles ("Missing a favourite? Add a place" / "Sharing is caring — Invite a friend"). XIX adds only a "WHERE TO NOW?" tracked-caps line above the header and the yellow "Open in My Main Man" button below.
- Recommendations from the group's circle surface first when they exist; otherwise MMM's area intelligence. Nothing is hand-curated by XIX.
- Tap anywhere → deep link to MMM (App Store if not installed).
- **Data:** fed the same way MMM itself is fed — the same Supabase source and the same query path, filtered to eat/drink and the course's location. No XIX-specific service.
- **Gating (MMM's, not XIX's):** the feed runs on MMM's own entitlement. An MMM Insider who signs into XIX gets the full feed. A non-Insider gets MMM's free allowance inside XIX, then hits MMM's gate; the upgrade offered is **MMM Insider**, not XIX Full. XIX Full never unlocks Where to now.
- **Locked state:** the same feed blurred behind one card in MMM's own styling — MMM white card, Insider badge, yellow "Become an Insider" button, footnote "Nothing to do with XIX Full". **The allowance copy must mirror MMM's actual free-allowance rule** (period and count); XIX does not invent one. Never a redesigned feed, never an XIX Full pitch.
- **Empty state:** MMM's one-line message and its two tiles; XIX adds nothing.
- No bookings, no payments, no "settle".

### 8.11 Rankings (passive)

- **Global board** on metrics a solo golfer can't fake: Stableford vs Level, birdies per month, rounds played, Rival Points.
- **Crew board:** private leaderboard among friends on the same metrics; serves friends in different cities with no game logic.
- Results count toward rankings when confirmed by at least one other player in the round; auto-confirm after 48 hours. "I object" freezes a result and prompts both parties to re-check.

### 8.12 Export

- Single renderer for on-screen, export and results. Exported at chat-bubble width (~322pt); stickers use the grid treatment (on the cell, partial cover, sender chips); live callout travels as a cream footer block; corner carries the join link; names/initials toggle.

### 8.13 Solo and personal

- Personal record per course, best round, streaks, average.
- **Ghost round:** race your own best round hole-by-hole at the same course (the only permitted "remote" opponent).

### 8.14 Onboarding and growth

- **Owner-scores-everyone:** one phone runs the group.
- **Result-link onboarding:** guests receive the results screen by link; tapping "Confirm my scores" presents Sign in with Apple (one tap, nothing to fill in) and keeps the round and medals. **Auth model:** Sign in with Apple only, on the shared Meuz auth, so an MMM user is the same account in XIX with no linking step; no anonymous tier. Guests can be scored by the owner all round without signing in.
- Every exported card and results image carries an invite link.
- Notifications: round invite, callout received, sticker played, results ready. No marketing pushes in V1.

### 8.15 Apple Watch (V1)

- Own-row score entry (Crown to change, tap to confirm); glance of the in-play strip and own standing; incoming callout as the CALLED OUT poster at wrist scale with SIGN IT / DUCK IT as targets (tap zones taller than the drawn bubbles to clear 44pt); SIGNED plays as confirmation; sticker-received haptics. Syncs through the paired iPhone; queues offline. No sending stickers, no export.

### 8.16 Round setup (as designed, Pass 6)
Home: "Same as last time" card (course, players, games) → Start it; "New round"; "Solo round"; personal record for the last course. New round: Course (search with recents; typing any name offers "use as a new course"; optional par as a row of 18 chips defaulting to 4; "Skip par" states which games grey out) → Players (owner first; rows show "Has XIX" / "By name"; recents as chips; contacts) → Games (opt-in matrix, players as columns; "Same games as last time"; FULL tags on locked rows; footer "2 of 2 games on free · the rest need Full"; par-dependent rows greyed with the reason on the row) → Share (QR/link, "Play hole 1"; late guests land on the current hole and the owner fills their earlier holes). Target: four taps for a returning group.

### 8.17 Join by link and guest confirm
No app: a page with the round (course, today, players, open row), "Open in XIX" / "Get XIX", "Scoring is free. No account needed to be scored by Ray." With the app: straight onto the live hole card, name pre-filled, "Claim this row" (holes already scored by the owner stay). Results link: "Your scores, kept by Ray" → "Confirm my scores" creates the account (anonymous auth, §8.14) and keeps the round and medals.

### 8.18 Cabinet and rivalry
Cabinet: riso patches on white, newest season first, tap → medal context card (patch, game, opponent · course · date, the round's exported card, Share). Rivalry: two names, head-to-head rounds won, streak line in accent, medals between you / callouts signed / ducked, medals between you, last five rounds with W/L and the stickers actually thrown in those rounds. Empties: patch silhouettes; "A rival appears after two rounds with the same person."

### 8.19 Rankings
Global and Crew tabs in the leaderboard style; metric pills (Stableford vs Level, Birdies, Rounds, Rival Points); rank, avatar, name, rounds · Level, movement caret in ink, metric right-aligned. Pending result row (warm surface) with Confirm / I object; "counts automatically in 41 hours". Crew board: private, "Invite to this crew", "New crew".

### 8.20 Games library and paywall
Library: every format, one-line plain rule, players required and par need at right, FULL tag where applicable; no pricing or promotion. Paywall: "Callouts and every game" — two numbered lines; Annual CAD 40 (CAD 3.33/month) / Monthly CAD 5; "Get XIX Full"; "Scoring and stickers stay free" · Restore. Contextual entry points: third game in the picker ("Free rounds run two games" — Swap a game / See XIX Full) and first callout attempt ("Calling someone out needs Full — you can still receive one, sign it and duck it" — Not now / See XIX Full).

### 8.21 First run (solo) and Settings
First run: "Play a round. Everything else follows from it." → Start a round; empty record; "Three rounds gives you a Level and Beat Your Average"; ghost round explained once a best round exists. After one solo round: "Same as last time — [course], solo"; record populated; Ghost round READY; Beat Your Average and Level marked ROUND 3; "Bring your group → Start a crew". Settings: Quiet mode by default, Names on export, Level (Auto · n / enter index), notifications (round invite, callout received, sticker played, results ready), Apple Watch, Sound (one cue), XIX Full status, Restore purchases, Delete account.

### 8.22 Snap the card (as designed)
Capture: frame overlay, "Fill the frame with the card", rows named before the shutter (player chips, "tap to name"), Enter by hand / Import shot alternatives. "Check it": "n cells to check", low-confidence cells in amber, written totals per player compared to the read, mismatch stated in one line ("Mo reads 49, the card says 48. Check hole 3."), every cell opens the hole-card number pad, "Confirm and see results". Poor read → blank grid at par.

## 9. Monetization

- **XIX Full subscription** (≈ CAD 40/yr, monthly option): full games library, callouts. Standalone; does not include MMM.
- **Where to now** earns nothing for XIX directly; it drives MMM installs and MMM Insider upgrades (product placement).
- **Sticker packs:** consumable IAP.
- **Post-V1:** sponsored callouts/challenges (contest rules per jurisdiction); MMM cross-promotion value.
- Never a revenue line: anything involving money between players.

## 10. Guardrails

- **Vocabulary:** no "bet", "wager", "stakes", "owe", "settle", "cash" anywhere in UI, copy, metadata or marketing. Use "games", "callouts", "medals", "results".
- **Money:** the app holds, links, records or displays no money. No payment deep links. Rival Points cannot be bought. No stake labels of any kind.
- **Stickers are never system judgements.** Attribution is mandatory; auto-placement is prohibited.
- **Contests:** any future prize-bearing challenge needs official rules, eligibility and jurisdiction handling (notably Quebec) before launch.
- **Privacy:** names/initials export toggle; no location broadcast beyond the selected course; guests' data limited to name and scores.
- **IP:** all stickers, medals and characters are original; no brand marks, no third-party characters, no tournament references.
- **Legal review** before submission on Canadian and US contest/skill-game rules and App Store guideline 5.3.

## 11. Technical

- **Client:** native SwiftUI, latest iOS kits; iPhone + Apple Watch in V1 (iPad later).
- **Backend:** Supabase (Postgres + Realtime), consistent with MMM and OM. Rounds, players and score rows as tables with row-level security (players write only their own row; owner writes any); Realtime channel per round for scores, callouts and stickers; client-side offline queue, last-write-wins per cell with a light merge notice. Shared auth with MMM/OM.
- **MMM integration:** XIX reads the feed exactly as MMM does — same Supabase source, same queries, filtered to eat/drink and the course location; MMM's entitlement (free allowance / Insider) is evaluated by the same rules MMM applies. No separate API layer; deep-link scheme to MMM.
- **Course data:** never a prerequisite. Free/open sources in order: OpenStreetMap (ODbL; hole geometry doubles as optional UI silhouettes; map gaps via OpenCourseMaps), OpenGolfAPI (US), Open Course data model (interchange), our own table (par read from cards / entered once; Vancouver hand-seeded). Paid sources deferred.
- **Recognition:** OM pipeline adapted for handwritten scorecard grids; on-device first, server fallback.
- **Animation:** Rive (native iOS runtime, SwiftUI view model). Sticker state machines own pinned/played and the callout pressed states. Packs are design deliverables.
- **Rendering/export:** one scorecard renderer for screen, export and results.
- **Analytics:** round created, players joined, games activated, hole cards opened, callouts sent/signed/ducked, stickers sent/played, nudges shown vs tray opened, card exported, results exported, where-next viewed/tapped, MMM handoff, paywall shown/converted.

## 12. Launch plan (V1)

- **Market:** global from day one; never restricted by geography. Any course anywhere works from a name. Cold launch, no partnerships. Vancouver is the validation locale and the first hand-seeded set, not a boundary.
- **Pre-launch validation:** 2–3 weekends with one group on a faked version to test callout uptake, hole-card usage mid-round, sticker behaviour and export.
- **App Store positioning:** category Sports; primary keyword "golf scorecard"; screenshots: the hole card with a CALLED OUT poster and two stickers, the grid with stickers, the results screen with medals, Where to now.
- **Locales:** English at launch; Traditional Chinese and Japanese follow (stickers are language-agnostic).
- **Content:** base pack of 12 at launch; first paid pack within the first update.

## 13. Success metrics

- **Activation:** rounds with ≥ 2 confirmed players.
- **Fun:** callouts per round; stickers sent and played per round; nudge → tray conversion; % of rounds with ≥ 1 export.
- **Retention:** crews (≥ 3 players) with rounds in 3 consecutive months.
- **Growth:** installs attributed to card/result links.
- **MMM:** where-next view rate; MMM handoff rate.
- **Revenue:** Full conversion at the 2-game limit and at the callout gate; pack attach rate; MMM Insider upgrades originating in XIX.

## 14. Competitive note

Synced group scorecards with auto-tabulated games are free from Hole19 LivePlay, GameBook and GolfNow Compete — table stakes. The differentiators — the hole card as a poster surface, callouts, attributed stickers, the exported card, snap-the-card, the results screen and Where to now — have no direct competitor and must be visible in the first 30 seconds of the listing and the app.

## 15. Roadmap (post-V1)

Trip mode (Ryder Cup sessions, season leagues, wooden spoon); crew sticker packs; sponsored callouts; course rating/slope and cross-course net games if the serious tier demands it; iPad "clubhouse" card; winter mode (sim-round entry, year-in-review card).

## 16. Remaining design scope (Pass 7)

Passes 5 and 6 are locked. Pass 7 closes the remainder: round menu (quiet mode for this round, edit players/games, snap shortcut, export, end round with missing-holes check, leave round); notification designs (callout received, results ready, sticker played, round invite; ink only); medal context card (game and callout variants); crew creation (three steps, empty board).

## 17. Open questions

1. Trademark clearance for "XIX".
2. Free-tier limit of two games per round — validate in the group test.
3. Sound: one slap cue in V1 (as designed in Settings), or per-pack cues later.

**Decided:** Picked up = double par / zero Stableford points. Where to now is fed the same way MMM is fed from Supabase. XIX Full is a standalone subscription; Where to now is MMM product placement gated by MMM's own free allowance and Insider tier. Level displays as a number.

---
*v0.3 — consolidates decisions through Claude Design Pass 6 (12 Sep 2026). Build can start: data model, scoring engine, sync, hole card. Next revision after Pass 7 and the group validation.*
