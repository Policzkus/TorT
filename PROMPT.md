# MASTER BUILD PROMPT — "Trick or Treat with Friends" (Roblox)

> **How to use:** tell Claude: **"Execute PROMPT.md — start Phase 0"** (later: "continue PROMPT.md").
> Claude: read this whole file at the start of every session, then read `docs/PROGRESS.md` to see where we are.
> Version 1 — written 2026-10-22. **Hard deadline: public launch Fri Oct 30, 2026; Halloween event Sat Oct 31.**
> **Version 2 direction — 2026-10-22 evening: read §V2 below first. It overrides every older section it conflicts with.**

---

## V2 · Direction update from the user (2026-10-22) — overrides older sections

### V2.1 What the user asked for (their words, lightly cleaned up)

> "Every neighbourhood must be its own map you teleport to using the bus. These maps should be big and highly
> detailed. Everything should look impressive. It must make you feel scared and immersed in the world. Everything
> should be in first person. The game should have a lot of costumes you can buy using candies. Candies let you buy
> costumes, skins for items and crates that can drop you boosts and souls. With candies you can boost your player
> stats (new buckets etc.). Souls (new currency) you use to go to new neighbourhoods and buy skins. With Robux you can
> buy candies, costumes (costumes should be very expensive so people buy them with Robux, except for a few first
> ones), lives and skins. There are a limited amount of lives; when you die you lose them. If you run out of lives you
> lose 50% of your progress. Costumes you bought stay after rebirth. Costumes give you like 5% more candy. We need very
> unique, very shock-value, eerie, creepy character designs (PSX style: stretched thin limbs, small uncanny heads,
> blurry low-poly textures). These characters are the ones in the doors of houses; every one of them should vary.
> When you first join you have no costume and you barely get any candy, so you need to buy one. Make 4 character
> models you start with when you don't have a costume. The game is up to 4 players (figure out how it should work; see
> V2.2): like horror games, you are alone
> with your friends on the server, not with other people. Put PSX-style effects on the camera. The game must be
> replayable: every playthrough should differ. Story is just an addition to the gameplay. Make a minimalistic HUD
> (reference: Watch Dogs: small monochrome icons in a corner, a contextual radial menu). We need separate maps for
> the inside of open buildings: a normal house with random loot spawns and a random layout. Make sure to do the best
> you can."
>
> Later the same day: "I need whole new character models for costumes and for starters. You don't play as your own
> Roblox character in this game."

### V2.2 Decisions (user's answers to Claude's questions, 2026-10-22)

- **Servers: Lobby + private runs.** Everyone joins a public **lobby** (shop, costumes, crates, party up with friends,
  leaderboards). **Start** teleports the party (1–4) to its own **reserved server of the same place** ("run" mode,
  `TeleportService:ReserveServer` + `TeleportAsync`; the server picks its mode from the reserved-server/teleport data).
  No strangers ever share a run. Teleports can't run in Studio, so Studio boots straight into run mode (lobby mode
  toggled by a dev flag), and the lobby↔run hop gets tested live.
- **Dying: inside houses only.** Streets are tense but safe (door jumpscares never kill). You die when a homeowner
  catches you while looting an open house: −1 life and your carried bucket is dropped (lost).
- **Out of lives: lose 50% of your banked candy**, then lives refill. Upgrades, souls, neighbourhoods and costumes
  are kept.
- **Maturity: Moderate (13+).** Go all-in on creepy PSX horror (uncanny homeowners, intense jumpscares). Still no gore
  or blood. Fill in the maturity questionnaire accordingly in Phase 7.

### V2.3 Design calls Claude made for the user (overridable; logged in PROGRESS.md)

- **A run = one Night** (18 min, Witching Hour finale) in a private server. At Dawn the party gets a results screen
  and returns to the lobby; anything still in your bucket at Dawn is banked. Every run rerolls house models per lot,
  house types, homeowners, open houses, interior layouts and loot, so every playthrough differs.
- **First person everywhere** (`CameraMode = LockFirstPerson`), with a first-person view of your hands holding the
  bucket/flashlight. Friends see your full character, costume and bucket.
- **PSX camera:** low saturation, crushed contrast, heavy fog, slight blur, a film-grain/dither + vignette overlay,
  gentle head-bob and handheld jitter, FOV ~70. A Settings toggle tones it down.
- **Minimal HUD:** small monochrome icons bottom-left (candy, bucket fill, lives, souls, clock), a contextual radial
  menu for interactions/menus (Watch Dogs-style), tiny toasts. This replaces the chunky cartoon HUD; menus become
  clean, dark and minimal.
- **No Roblox avatars.** You always play as one of the game's own characters: every starter kid and every costume
  is a whole character model (AI mesh cut into head/torso/arms/legs, rigged onto a custom Humanoid, with stiff
  PSX-style procedural walk/idle animation). Wearing a costume swaps your whole character model.
- **Starter characters:** 4 base kid characters (picked in the lobby on first join, free). With **no costume**,
  homeowners give almost nothing (×0.15 candy), so the first costume is cheap and the tutorial buys it.
- **Costumes:** lots of them (target 30+ at launch). Each gives **+5% candy** (rarer ones more) and has a preference
  tag (Classic/Spooky/Cute/Funny: matching the homeowner's preference gives +40%). The first ~4 are cheap in candy;
  the rest get steeply more expensive in candy, with a Robux price as the shortcut. **Costumes persist through
  rebirth.**
- **Currencies:** **Candy** (earned) buys stat upgrades/buckets, costumes, item skins and **crates**. **Souls** come
  from crates, rebirth and rare events, and buy **neighbourhood access** (replacing candy gate prices) and skins.
  **Robux** buys candy packs, costumes, lives and skins.
- **Crates** (bought with candy, odds always shown) drop boosts (potions), souls and skins. They're CS-style reels
  like §3.10, which become the crate opening. Robux-bought random items stay gated by `PolicyService`.
- **Lives:** 3 max, +1 every 20 min of real time up to the max, Robux packs for more. Death: −1 life, carried candy
  lost, respawn at the street's bus stop after a short "you fainted" fade. Out of lives → −50% banked candy, lives
  refill.
- **Homeowners:** a large roster of uncanny PSX characters (AI meshes plus per-house random scale/colour/stretch
  variations so no two doors look alike). They appear in the doorway when you knock, and the same characters stalk
  you inside open houses.
- **Neighbourhood maps:** each neighbourhood is its own big, detailed map (bus stop arrival, winding streets, side
  alleys, props, fog, story notes), built far apart in the same run place and reached only by the bus. **House
  models get scarier every neighbourhood (3+ unique models each).**
- **Interiors:** looting an open house teleports you to a separate interior map: a normal house with a procedurally
  generated layout (room templates) and random loot spawns, plus the homeowner hunting you.
- **Story (light):** found notes and Witching Hour hints about why the town's homeowners changed. Optional; never
  blocks play.
- **Scope vs the Oct 30 deadline:** the run loop, first person/PSX, lobby/party, costumes, lives/death, interiors and
  **Cardboard Court, Maple Lane and Pumpkin Hollow as full maps** are P0. Raven Ridge, Mansion Hill and Blackwood
  Estates ship as fast as possible after (weekly updates are acceptable, as in §7).

### V2.4 Revised phase plan (replaces the dates in §6 from Phase 2 on)

| Phase | Target | Build |
|---|---|---|
| 2 · Doors come alive | ✅ Oct 22 | (done: mini-games, house types, night cycle, jumpscares, settings) |
| 2.5 · Horror pivot | Fri Oct 23 | First person + PSX camera, minimal HUD + radial menu, lobby/run modes and party teleport, starter characters + no-costume penalty, lives + death, souls currency, uncanny homeowners in doorways, 3 AI house models per neighbourhood |
| 3 · Maps & heists | Sat–Sun Oct 24–25 | Separate big maps per neighbourhood (N1–N3) + bus between them, interior maps (random layout + loot), homeowner AI, caught = death, escape |
| 4 · Progression | Mon Oct 26 | Costume shop (30+), crates (CS reel) with boosts/souls/skins, item skins, souls shop/neighbourhood access, rebirth (costumes kept), economy sim pass |
| 5 · Retention & social | Tue Oct 27 | Tutorial, daily rewards, quests, run results screen, lobby leaderboards, codes, story notes |
| 6 · Money & polish | Wed Oct 28 | Robux: candy packs, costumes, lives, skins, passes; receipts; sound/VFX/perf pass |
| 7–8 | Oct 29–30 | Release candidate, launch (unchanged) |

---

## 0. The user's original vision (do not lose this)

> "Trick or treat with friends. You go around neighbourhoods from poor to rich and you ask for candy, with jumpscares,
> and some homes open for looting. Candy is the currency. You can drop rare candy that when you eat it you get a lil
> CS case type thing and you unlock upgrades and better candy or bigger candy bags. If your candy box gets full you
> reset, and you upgrade your buckets. With time you progress to better, bigger but scarier neighbourhoods. At the
> door there needs to be some sort of skill check affecting how much candy you get. When you get caught while looting
> an open house you get punished and half of your candy disappears. The game must be addicting, a lot of in-game
> things to buy. It needs to be perfect."

The user chose: **Rojo workflow** · **launch Oct 30/31** · **bucket→stash + Candy Box→rebirth (Claude's call)** · **mixed door mini-games**.

---

## 1. Mission

Build a polished, highly replayable Roblox simulator/horror-lite game and ship it publicly by **Oct 30, 2026**.
It has to feel great in the first 60 seconds, give something new every few minutes, and give players a reason to come back tomorrow.
Ship a game that is complete and bug-free with fewer features rather than a broken one with more. Data safety and the core loop are untouchable.

### Design pillars (use these to settle every decision)
1. **Reward cadence:** a small reward every ~10 seconds (candy pop), something meaningful every ~3 minutes (an upgrade or a rare candy), something big every ~15 minutes (a new neighborhood or a big item), and something per session (a rebirth or the daily streak).
2. **Variable rewards:** rare candy drops, case rarities, Full-Size Bar houses, perfect streaks.
3. **Real risk/reward choices:** stash now or keep carrying, take one or take ALL, loot the house or play safe.
4. **Always a visible next goal:** the next upgrade price has a progress bar, and the next neighborhood gate glows at the end of the street.
5. **Flex:** huge buckets, familiars, auras, rank titles, unbox announcements, leaderboards.
6. **Juice everywhere:** every action gets a sound, a tween, a number pop and a particle.
7. **Never unfair:** banked candy is never lost, odds are always shown, walks are short (teleports), jumpscares have an intensity setting.
8. **Friends make it better:** the party bonus and friend bonus mean playing together is strictly better.

---

## 2. Rules for Claude while executing

1. **Work phase by phase (section 6).** Each phase ends with its Definition of Done. Update `docs/PROGRESS.md` (phase status, decisions, known bugs, next steps) at the end of every phase *and* before any long pause, so a fresh session can resume cold.
2. **Config-driven.** Every tunable number, name, price, drop rate and asset ID lives in `src/ReplicatedStorage/Shared/Config/*`. Logic files contain no magic numbers.
3. **Server-authoritative.** The client only sends *intent* and *inputs*. The server computes candy, rolls, prices, detection and saves (section 5.5).
4. **Never invent asset IDs or APIs.** Only use sound/mesh/decal IDs that were verified (found in the Creator Store, or given by the user). Unknown IDs stay `0` and the code must degrade gracefully. Check Roblox APIs against create.roblox.com/docs before relying on memory, especially anything that might be deprecated.
5. **Strict Luau** (`--!strict`), formatted with StyLua, lint-clean with Selene. Small modules with clear names.
6. **Git commit at the end of every phase** (and before risky refactors). Use the commit attribution the harness specifies.
7. **Verify.** Run Lune tests for pure logic (formulas, loot tables, economy sim). Playtest in Studio through the Studio MCP if it's set up, otherwise give the user a short **2-minute test script** ("press Play, do X, you should see Y") at each checkpoint.
8. **Kid-safe and Roblox-compliant:** no gore or realistic blood, stylized monsters, case odds shown before every open, Robux-bought random items gated by `PolicyService`, no rewards for likes or favorites, no free-text player input (or filter it with `TextService` if any is ever added).
9. **When behind schedule:** cut P1 items (section 7). Never cut data safety, the core-loop feel, mobile support, or receipt handling.
10. Propose improvements whenever you spot them, but log scope changes in PROGRESS.md and don't silently expand scope.

---

## 3. Game design

### 3.1 Core loop

```
 KNOCK ON DOOR ─► MINI-GAME ─► CANDY (+ maybe RARE CANDY) ─► BUCKET fills ─► (overflow is wasted!)
      ▲                                                            │
      │      LOOT OPEN HOUSES / "TAKE ALL" BOWLS  (caught = lose ½ bucket)
      │                                                            ▼
  UPGRADES ◄── SPEND ◄── CANDY BOX (bank, safe) ◄── STASH at drop-off point
      │                          │
      ▼                          ▼  box 100% full
  NEW NEIGHBORHOODS          REBIRTH ─► permanent ×multiplier, Souls, new zones, higher upgrade caps

  RARE CANDY ─► EAT ─► CS-STYLE CASE SPIN ─► bucket skins · costumes · familiars · potions · jackpots
```

### 3.2 World layout
- One long, winding night road. **Home Street (hub)** → gate → Neighborhood 1 → gate → 2 → … → 6. Gates show price and rebirth requirement on a glowing billboard. Each scarier neighborhood is visible beyond its gate to make players curious.
- **Hub contains:** spawn, the main Candy Box drop-off, *Sweet Tooth's Shop* (upgrades and consumables), the *Soul Altar* (rebirth and Soul Shop), the *Costume Rack*, leaderboards (physical boards), the Robux store kiosk, and the **Spooky School Bus** teleporter to any unlocked neighborhood. Players hate long walks.
- Each neighborhood has a **Candy Box drop-off** at its entrance (a glowing chest; stand in its circle to deposit) and a bus stop back to the hub.
- **Art: procedural from code.** A deterministic, seeded world builder generates houses, streets, props and lighting at server start, so the layout is identical every time. **Swap-in support:** if `Workspace.Handmade.<NeighborhoodId>` or `ReplicatedStorage.Assets.<Category>.<Name>` exists, use that model instead of the procedural one. The user can drop in Toolbox or handmade models later without code changes. Add a Studio command-bar snippet, `BakeWorld`, to preview the world in edit mode.

### 3.3 Neighborhoods (launch set = 6; starting numbers, tune with the sim)

| # | Name | Wealth / vibe | Unlock | Base candy per door | Scare | Homeowner when looting | Rare candy drops |
|---|---|---|---|---|---|---|---|
| 1 | **Cardboard Court** | trailer park, chain-link fences, warm porch lights | free | 1–3 | ★☆☆☆☆ | Sleepy Grandpa (slow, naps) | Glow Gummy |
| 2 | **Maple Lane** | small brick houses, picket fences, falling leaves | 250 | 4–8 | ★★☆☆☆ | Night-shift Mom | Glow Gummy, Witch's Taffy |
| 3 | **Pumpkin Hollow** | big decorated suburbs, fog machines, lawn skeletons | 2,500 | 15–30 | ★★★☆☆ | Flashlight Dad + small dog | Witch's Taffy, Ghost Jawbreaker |
| 4 | **Raven Ridge** | Victorian hill, ravens, iron fences, heavy fog | 25K + **Rebirth 1** | 60–120 | ★★★★☆ | Creepy Butler (fast, silent) | Ghost Jawbreaker, Vampire Truffle |
| 5 | **Mansion Hill** | gated mansions, hedges, fountains, intercom gates | 250K + **Rebirth 3** | 250–500 | ★★★★☆ | Security guard, guard dogs, cameras | Vampire Truffle, Cursed Candy Corn |
| 6 | **Blackwood Estates** | haunted mansions around a cemetery, red moon | 2.5M + **Rebirth 5** | 1K–2K | ★★★★★ | Monster owners (Witch, Count Sugula) | Cursed Candy Corn, Golden King-Size Bar |

Each neighborhood has its own palette, Atmosphere and ColorCorrection, music, house style set (Trailer / Cottage / Suburban / Victorian / Mansion / Haunted), 12–18 houses, and NPC types. Lighting blends client-side when you cross a zone boundary.
Post-launch neighborhoods: *Count Sugula's Castle*, *The Candy Factory*, *Witchwood Swamp* (one per weekly update).

### 3.4 Night cycle and live events
- **It's always night.** One "Night" = **18 real minutes**, from in-game 6:00 PM to midnight (3 real minutes per in-game hour). The clock is in the HUD.
- **Witching Hour** (last 3 minutes of each Night): ×2 candy, +1 mini-game difficulty, double trick-house chance, red fog and a music swap. A countdown banner appears 60 seconds before. This climax keeps players in the server.
- **Dawn** (midnight): fade transition, "NIGHT 2". House states reshuffle (which houses are open, tricks, bowls) and per-house cooldowns reset.
- **Full-Size Bar House:** every ~4 minutes a random house in an occupied neighborhood glows gold with a light beam visible from far away, and a server announcement goes out. The first 6 visitors get ×10. It lasts 60 seconds. Players rush to it, which is the point.
- **Blood Moon (Halloween):** auto-activates from **Oct 31 00:00 UTC to Nov 1 08:00 UTC**. Red sky, ×2 candy, plus the exclusive **Blood Moon Lolly** rare candy (an event case with event-only items) and an event familiar. A hub countdown runs before it starts. All of this is driven by config (start/end timestamps), so it needs no republish.
- **Candy Goblin** (P1): a goblin carrying a sack that runs around a neighborhood. Tag it for a loot burst.

### 3.5 House types (rolled per house, per Night)

| Type | Tell (how players spot it) | What happens | Weight N1 → N6 |
|---|---|---|---|
| **Normal** | porch light on | knock → mini-game → candy | 60 → 30 |
| **Decorated** | heavy decorations | ×1.5 candy, +1 difficulty | 10 → 20 |
| **Trick House** | flickering light, nothing unusual otherwise | jumpscare + forced **Nerve Hold**. Holding through it = "BRAVE!" ×2.5 | 0 (N1) / 5 → 25 |
| **Take-One Bowl** | bowl on the porch with a "PLEASE TAKE ONE" sign | *Take one* = safe ×1. *Hold "TAKE ALL"* (3 s) = ×12, with a 35% chance the owner bursts out (jumpscare) and you're **caught** | 10 → 5 |
| **Open House** | door ajar, lights off, 👀 icon | **looting** (3.9). 2–4 per neighborhood per Night | fixed count |
| **Lights Off** | dark | nobody answers | 10 → 5 |
| **Full-Size Bar** | gold beam (event) | ×10 for the first 6 visitors | event |

**Per-player cooldown:** after you visit, the door shows 💤 plus a timer (only you see it). It resets at Dawn or after 4 minutes, whichever comes first.
**Homeowner preference icon** above each door (🎃 Classic / 👻 Spooky / 🐱 Cute / 🤡 Funny): a matching costume tag gives **+40%** candy. This makes collecting costumes matter.

### 3.6 Door mini-games (each door rolls one, weighted by neighborhood)

The **difficulty** of a roll = neighborhood tier (1–6) +1 if Decorated +1 during Witching Hour (clamped to 1–8). Every mini-game scores **MISS / GOOD / GREAT / PERFECT**.

| Mini-game | How it plays | Scaling with difficulty |
|---|---|---|
| ⏱ **Timing Bar** | A needle sweeps a bar. Tap/Space/A when it's in the zone. | zone widths Good/Great/Perfect go from 30/14/6% to 16/7/2.5%, sweep time 1.6 s → 0.7 s, 2 hits needed from difficulty 4, the needle can reverse from difficulty 6 |
| 🥁 **Knock Rhythm** | The door knocks a pattern (audio and visual). Repeat it in time. | 3 → 7 knocks, 90 → 140 BPM, syncopation, *fake* creak sounds to ignore from difficulty 5 |
| 😨 **Nerve Hold** | Hold the button while the house gets scary (flickering lights, face in the window, whispers). Letting go early = flinch. | duration 3 → 7 s, stronger scare events, "let go…" whisper traps from difficulty 5. Ends with the jumpscare. |
| 🎭 **Costume Line** | The homeowner asks something ("What's the magic word?"). Pick the answer they'd like. Hints are their personality and the door decorations. | 2 → 4 options, 8 → 4 s timer. Write **40+ kid-friendly lines** across personalities: Grumpy Gus (polite), Witchy Wanda (rhymes), Coach Carl (hype), Lady Victoria (manners), Count Sugula (dramatic) |

Weights: N1 Timing 60 / Costume 40. N2 Timing 40 / Knock 30 / Costume 30. N3+ Timing 30 / Knock 25 / Costume 25 / Nerve 20. Trick houses always roll Nerve.

**Grade multipliers:** MISS ×0.4 · GOOD ×1 · GREAT ×1.6 · PERFECT ×2.5.
**Sweet Streak:** each consecutive GREAT/PERFECT adds +10%, up to +100% at 10. A MISS resets it. The streak meter sits on the HUD with fire VFX at 5+. Best streak goes on a leaderboard.
Mobile: one large tap target. Console: gamepad A. PC: Space or click. Every mini-game must finish in ≤ 4 s at low difficulty so doors never feel slow.

### 3.7 Candy formula (server only, in `Shared/Modules/Formulas.luau`, unit-tested)

```
DoorCandy = round( Base(N, houseType)            -- random in neighborhood range × house-type mult
          × Grade × (1 + Streak)
          × Charm      -- 1 + upgrade% + costume% (+40% preference match)
          × Rebirth    -- 1 + 0.4 × rebirths (tune)
          × Familiars  -- 1 + sum(equipped familiar %)
          × Social     -- 1 + 0.10 × party members within 40 studs (max 3) + 0.10 × Roblox friends in server (max 3)
          × Boosts     -- potions, Server Sugar Rush
          × Passes     -- 2x Candy ×2, VIP ×1.25, Premium ×1.1, group member ×1.1
          × Event )    -- Witching Hour ×2, Blood Moon ×2; total event mult capped at ×4
```
Rule: **bonuses add within a category and multiply across categories** (this keeps inflation under control). Candy pops fly from the door into the bucket in the UI.

### 3.8 Bucket → Stash → Candy Box → Rebirth
- **Bucket = carried candy** with a capacity. Your character visibly **holds the bucket model**, which gets bigger with each tier and fills up with candy as it gains. Candy beyond capacity is **lost** ("OVERFLOW −12 🍬" and the bucket shakes). That's the push to stash or upgrade.
- **Stash:** stand in a drop-off circle and the candy pours into your **Candy Box (bank)** with a satisfying sound and animation. Banked candy is **never** lost.
- **Candy Box capacity = this life's rebirth goal:** R0 25K, R1 150K, R2 600K, R3 2.5M, R4 10M, R5 40M, then ×4 each rebirth. When the box hits 100%, deposits stop, the box glows, and the **REBIRTH** button pulses. You *can* spend to free up space, but the incentives (new zones, multiplier, Souls) make rebirthing the obvious move. This is the user's "candy box full → reset".
- **Rebirth resets** banked and carried candy and all shop upgrade levels. **It keeps** case items, familiars, unlocked neighborhoods, Souls and Soul perks, gamepasses, index, quests and lifetime stats.
- **Rebirth gives:** +40% permanent candy (tune), Souls (`1 + floor(R/2)`), unlocks for rebirth-gated neighborhoods, **+5 max levels on every upgrade track**, a new rank title and an overhead aura tier. Plus a big cinematic (you "rise from the grave").
- Constraint for tuning: every gate or upgrade price in life R must be ≤ 50% of the box capacity in life R.

### 3.9 Looting open houses
- *Sneak In* prompt → fade → **interior** (generated per house style from templates, placed in a hidden area far off-map, built when the house opens and removed at Dawn). Interiors can be bigger than the outside (mansions). Several players can loot the same interior, which allows co-op: one distracts while another grabs.
- **Loot spots** (hold the prompt, which makes noise):
  - Bowl: 3× the door average.
  - Jar: 6×.
  - Hidden stash: 10×, only visible with Flashlight level ≥ 2.
  - **Safe**: Mansion and Haunted only, 25×, 30% rare candy chance. Opening it is a Timing Bar "crack the safe" mini-game.
- **Noise meter** (HUD). Running, jumping, grabbing and bumping props add noise; crouch (C / mobile button) is slow and quiet. **The server computes noise** from character state and velocity. Never trust a client noise value.
- **Homeowner AI** (PathfindingService state machine): `Sleep/Idle → Suspicious (❓, walks toward noise) → Chase (❗) → Search (8 s) → Return`. Detection uses a 90° vision cone, line-of-sight raycasts, a light factor (crouching in darkness halves detection) and the noise radius. Speeds increase per neighborhood (N1 12 → N6 22). The player's walk is 16+ and sprint 24+ with stamina, so escaping is possible but tense. N5 adds cameras and dogs. N6 owners can blink-teleport short distances.
- **Escape:** get out the front door = safe, "GOT AWAY!" (counts for quests).
- **Caught** (owner touches you): grab animation, red flash, a funny/scary line ("THOSE ARE FOR THE TRICK-OR-TREATERS!"), and **you lose 50% of the candy in your BUCKET** (Insurance pass: 25%; the Second Chance soul perk can cancel it). You're thrown onto the lawn and that house is locked for you for the rest of the Night.
  - *Decision on the user's behalf:* "half of your candy" means **carried** candy, not banked. That keeps it scary without making players rage-quit, and it rewards stashing before a heist.
- **Hide spots** (closets, under beds) and **Smoke Bomb / Decoy Pumpkin** consumables: P1.

### 3.10 Rare candy and the CS-style case opening
- **Rare candy drops** from doors (≈0.2–1.2% base per neighborhood, ×1.5 on a PERFECT) and loot spots (≈1–4%), modified by Luck. **The tutorial guarantees one on door #5.**
- Each rare candy **is** a case with its own loot table:

| Rare candy | Drops in | Theme of contents |
|---|---|---|
| Glow Gummy | N1–N2 | starter buckets, basic costumes, bat/cat familiars |
| Witch's Taffy | N2–N3 | witchy costumes, cauldron bucket, toad familiar |
| Ghost Jawbreaker | N3–N4 | ghost costumes, spectral bucket, ghost familiars |
| Vampire Truffle | N4–N5 | vampire set, coffin bucket, bat swarm |
| Cursed Candy Corn | N5–N6 | cursed items, scarecrow, crow familiars |
| Golden King-Size Bar | N6 + safes | best-in-slot items |
| Blood Moon Lolly | **event only** (Oct 31) | event-exclusive items, never return |

- **Rarities (CS colors) and fixed odds:** 🔵 Mil-Spec 79.5% · 🟣 Restricted 16% · 🩷 Classified 3.2% · 🔴 Covert 1.0% · 🟡 Exceedingly Rare 0.3%.
  **Pity:** guaranteed 🩷+ within 20 opens of the same case, 🔴+ within 100. Pity progress is shown in the UI.
- **Opening UX:** a HUD button with a glowing count badge → choose a rare candy → the character *eats* it (animation and crunch sound) → a **horizontal reel** of ~45 item cards (ViewportFrame previews, rarity-colored bottom strip) scrolls under a center marker and decelerates over ~5.5 s (Quint out) with a tick sound as each card passes → the winning card zooms in with a rarity burst. 🔴/🟡 trigger a screen flash, confetti and a **server-wide announcement** ("Filip unboxed 🔴 COVERT Mini Reaper!").
  **Honest reel:** the server rolls the result first, and filler cards are drawn from the real odds. No fake near-miss stacking. Landing offset within the winning card is random.
- **"View odds & contents"** is on every case before opening (required). The Fast Open pass gives ×3 animation speed and Open ×5.

### 3.11 Items (author ~75 items in `Config/Items.luau`; models are procedural with swap-in)

| Category | Effect by rarity (🔵 → 🟡) | Notes |
|---|---|---|
| **Bucket skins** | +10 / 20 / 35 / 60 / 100% capacity on top of the shop tier | 🔴/🟡 get a perk (e.g. auto-collect overflow at 25%) |
| **Costumes** | +5 / 10 / 18 / 30 / 50% to Charm *or* Stealth *or* Speed | carry a preference tag (Classic/Spooky/Cute/Funny). Visible on the character, built from parts |
| **Familiars** (pets) | +5 / 10 / 20 / 35 / 60% candy | 🟣+ get an ability: Bat warns when an owner is near, Black Cat +Luck, Ghost −noise, Spider grabs loot faster, Mini Reaper +candy +luck. Rendered client-side and follow you. **3 slots** (+2 pass, +1 soul perk). P1: **Fuse 5 identical → Golden** (×1.5) |
| **Potions** | 2× Candy / 2× Luck / Silent Steps, 5–15 min | 🔵/🟣 only. Timers count **play time**, not real time |
| **Jackpots** | Candy = X minutes of your earn rate · Souls | Souls only at 🔴/🟡 |

Inventory: cap 300, "Equip Best", lock, sort by rarity. P1: melt duplicates into candy.
**Index / Collection book:** shows every item (silhouette until owned). P1: completing a case set gives a permanent +5% candy.

### 3.12 Candy shop: upgrade tracks (reset on rebirth; `maxLevel = 10 + 5 × rebirths`; `cost = base × growth^level`)

| Track | Effect per level | Notes |
|---|---|---|
| **Bucket tier** | capacity: Paper Bag 15 → Plastic Pumpkin 50 → Pillowcase 120 → Trick Sack 300 → Trash Bag 750 → Laundry Basket 2K → Wheelbarrow 5K → Wagon 12.5K → Coffin 30K → Cauldron 80K → Haunted Wardrobe 200K → Black Hole Bucket 1M (tiers 13–15 need rebirths) | **visible model change every tier** |
| **Sneakers** | walk speed 16 → 26, more sprint stamina | |
| **Charm** | +10% door candy | |
| **Stealth** | −6% noise | |
| **Luck** | +8% rare candy chance | |
| **Flashlight** | range and brightness; level 2 reveals hidden stashes, max level outlines homeowners through walls | 5 levels |

Also sold for candy: **consumables** (Smoke Bomb, Decoy Pumpkin, Candy Magnet: P1), **basic costumes** (6 shop costumes), and **cosmetics** (trails, footstep VFX, name colors) as late-game candy sinks (P1).
Every shop entry shows "X% to afford" progress, and buttons glow when affordable.

### 3.13 Soul Shop (permanent; Souls come from rebirth and rare jackpots)
- **Head Start:** start each life at bucket tier +2 (3 levels).
- **Eternal Charm:** +10% candy (5 levels).
- **Lucky Bones:** +10% luck (5 levels).
- **Extra Familiar Slot** (1 level).
- **Ghost Hands:** loot 30% faster (3 levels).
- **Second Chance:** 10/20/30% chance to wriggle free when caught.
- **Keep It:** keep one upgrade track's levels through rebirth.

### 3.14 Pacing targets (the source of truth; the starting numbers above are just a first guess)
A **Lune economy simulator** (`tests/economy_sim.luau`) models an average player (grades: 10% MISS / 40% GOOD / 35% GREAT / 15% PERFECT, realistic doors per minute per zone, stash trips, greedy best-value buying, rebirth when the box is full). It prints a milestone timeline. Tune the config until these are met:

| Milestone | Target (cumulative play time) |
|---|---|
| first candy pop / first stash | 0:15 / 1:00 |
| first upgrade bought | ≤ 2:00 |
| first rare candy + case open | ~2:00 (scripted) |
| Maple Lane unlocked | 5–7 min |
| Pumpkin Hollow unlocked | 20–25 min |
| first Rebirth | 45–60 min |
| Rebirth 3 / Mansion Hill | ~3 h |
| Rebirth 5 / Blackwood Estates | ~7–8 h |
| something affordable | at least every ~3 min during the first hour |

Numbers are doubles: format with K/M/B/T/Qa/Qi suffixes and keep late-game values below 2^53.

### 3.15 Retention systems
- **Tutorial quest chain** (first ~10 min, with a guide arrow; returning players skip it): knock 3 doors → stash → buy Plastic Pumpkin → eat your first rare candy → take one from a bowl → loot an open house → unlock Maple Lane. Track every step with `AnalyticsService` funnel events.
- **Daily login calendar** (7 days, scaled to progression). Day 7 = a guaranteed 🟣+ rare candy roll. Missing a day resets the streak, with a 1-day grace.
- **Playtime gifts** in-session at 3 / 6 / 10 / 15 / 20 / 30 / 45 / 60 min (resets each session). This keeps players in the server.
- **Daily quests** (3, one free reroll). For example: "Get 10 PERFECTs", "Loot 2 houses without getting caught", "Visit a Full-Size Bar house". Weekly quests are P1.
- **Leaderboards** (OrderedDataStore, top 50, refreshed every 2 min, shown on physical hub boards): lifetime candy, rebirths, doors knocked, best streak. In-server `leaderstats`: Candy, Rebirths.
- **Codes** (config list with expiry): `HALLOWEEN`, `SPOOKY`, `LAUNCH`.
- **Badges** (P1): first rare candy, first rebirth, caught 10 times, PERFECT streak 10, each neighborhood.
- **Group bonus** (P1): ×1.1 candy and a chat tag if the player is in the user's Roblox group.
- **Announcements feed:** unboxes, Full-Size Bar houses, Witching Hour, Server Sugar Rush purchases.

### 3.16 Friends / social
- **Party** (max 4, invite players in the server from the player list or by clicking them): members get a highlight outline through walls, the party bonus at doors, and a shared "Party Knock". If 2+ members knock the same door within 3 s, the owner says "Oh, a whole group!" and everyone gets +15% on top.
- **Friend bonus:** +10% per Roblox friend in the server (max +30%), shown on the HUD with an **"Invite Friends"** button (`SocialService:PromptGameInvite`). This bonus is the growth engine.
- Max server size: **12**. Private servers enabled at a low price.

### 3.17 Monetization (Robux; prices are suggestions for the user to approve)
Every Robux item speeds things up or is cosmetic. Nothing is locked behind Robux only. IDs live in `Config/Monetization.luau`. Products with an ID of `0` are hidden automatically.

| Gamepass | Effect | Price |
|---|---|---|
| 2× Candy | ×2 all candy | 249 |
| VIP | ×1.25 candy, gold name and chat tag, VIP Lounge in the hub with its own Full-Size Bar house every 5 min | 349 |
| Mega Bucket | +75% bucket capacity | 149 |
| Lucky Charm | +50% rare candy chance | 199 |
| +2 Familiar Slots | | 199 |
| Ninja Sneak | −40% noise, +15% loot speed | 129 |
| Candy Insurance | lose 25% instead of 50% when caught | 99 |
| Remote Stash | stash from anywhere (60 s cooldown, disabled inside houses or while chased) | 179 |
| Fast Open | ×3 case speed + Open ×5 | 79 |
| Starter Pack | exclusive familiar "Lil' Boo" + 30 min 2× Candy (offered to new players) | 49 |

| Developer product | Effect | Price |
|---|---|---|
| Candy Pack S / M / L | = 10 / 45 / 180 minutes of *your* current earn rate (computed server-side) | 29 / 99 / 349 |
| 2× Candy Potion (30 min) | | 49 |
| **Server Sugar Rush** | whole server gets 2× candy for 10 min, buyer gets a shout-out | 99 |
| Rare Candy bundles | **paid random items:** show odds, hide entirely when `PolicyService` says `ArePaidRandomItemsRestricted` | 79 / 249 |

- `ProcessReceipt` must be **idempotent**: store `PurchaseId` in the profile, grant and save before returning `PurchaseGranted`, and follow the official ProfileStore receipt pattern.
- Premium members get ×1.1 (this also earns Premium Payouts).

### 3.18 UI / UX
- **Style:** chunky cartoon Halloween. Dark purple panels `#2A1B3D`, orange accents `#FF8A00`, slime-green highlights `#7CFF4F`, bold white text with a dark stroke. Font: FredokaOne for headings, Builder Sans for body text. Bouncy Back-easing open/close tweens, buttons scale 1.05 on hover and 0.95 on press, a click sound on every button.
- **HUD:**
  - Top: banked candy (rolling counter), **bucket fill bar** with the bucket icon, Souls, Night clock.
  - Left: menu buttons (Shop, Inventory, Cases [badge], Quests, Rebirth, Daily, Index, Store, Settings).
  - Right: active boosts with timers, quest tracker, friend bonus with Invite.
  - Bottom (mobile): Sprint, Crouch, Remote Stash.
  - Center top: toasts and announcements.
  - Floating "+24 🍬" pops.
- **Settings:** music volume, SFX volume, **Jumpscare intensity: Full / Reduced (no sting, no flash) / Off ("BOO!" text)**, reduce flashing, UI scale.
- Works at phone size (Studio Device Emulator: iPhone SE up to an iPad), on gamepad (selectable UI, prompts), and on PC.

### 3.19 Audio and visuals
- **Lighting:** permanent dusk-to-night gradient, Atmosphere and ColorCorrection per zone, subtle Bloom, neon jack-o'-lanterns, a limited number of PointLights per house, client-side flickering street lamps, a big moon (Sky.MoonAngularSize), particles (leaves, fog wisps, fireflies).
- **Jumpscares** (client-side, `JumpscareController`): the camera locks onto the door, the door slams open, a stylized monster (procedural from parts, or a swap-in model) lunges at the camera with a tween, then camera shake, a red vignette flash and a loud sting. Intensity follows Settings. **Global scare cooldown of about 45 s** so they stay effective (scares that come too often stop being scary). **Ambient scares** in N3+: a figure under a streetlamp that vanishes, something running between houses, a face at a window.
- **Audio:** wind, crickets, distant howls, knock/creak/door sounds, candy-pour sound, case ticks and reveal, heartbeat during chases, music per neighborhood. **Only verified Roblox Creator Store IDs** (Roblox-uploaded or licensed), all in `Config/Sounds.luau`, preloaded, with silent fallback.
- **Maturity:** keep monsters cartoon-stylized and gore-free, and aim for a **"Mild"** maturity label. Check the current Roblox guidelines for what pushes "fear" content into a higher label before finalizing scare intensity.

---

## 4. Do's and don'ts for "addicting"
- **Do:** constant goals, generous early rewards, satisfying feedback, social flex, events, streaks, honest variable rewards.
- **Don't:** pay walls, hidden odds, fake near-misses, losing banked progress, long walks, unskippable long animations for repeat actions, tiny unreadable mobile buttons.

---

## 5. Technical spec

### 5.1 Toolchain (Phase 0; ask the user before each download)
- **Rokit** (toolchain manager) → `rojo`, `lune`, `stylua`, `selene` (+ `wally` only if a package needs it). Pin versions in `rokit.toml`.
- **Rojo:** `rojo serve` + the Studio plugin (`rojo plugin install`) for live sync. `rojo build -o build/TorT.rbxlx` for a standalone place file.
- **ProfileStore** (loleris) for player data: session locking and receipt handling. Verify the current official source and version at install time. Vendor it into `src/ServerScriptService/Server/Packages` if Wally isn't used.
- **Optional but strongly recommended: Roblox's official Studio MCP server**, so Claude can run code in Studio, start playtests and read the Output window directly. Check the current install method (newer Studio versions may have it built in) and set it up with the user's permission.
- VS Code: suggest the Rojo + Luau LSP extensions.

### 5.2 Project layout
```
TorT/
  default.project.json  rokit.toml  stylua.toml  selene.toml  .gitignore
  docs/            PROGRESS.md · LAUNCH_CHECKLIST.md · ECONOMY.md (sim output + tuning notes)
  tests/           run.luau (runner) · lib/rbx.luau (Roblox-require shim) · *.spec.luau · economy_sim.luau
  src/                                   -- Rojo maps: shared → ReplicatedStorage.Shared,
                                         --   server → ServerScriptService.Server, client → StarterPlayerScripts.Client
    shared/
      Config/      Economy · Neighborhoods · HouseTypes · Minigames · Upgrades · Items · Cases · SoulShop
                   Monetization · Quests · DailyRewards · Events · Codes · Sounds · Ranks · Dialogue
      Modules/     Formulas · LootTable (seeded RNG, pity) · Format (number suffixes) · Net (remote registry)
                   Loader · Types · Rarity · Signal · RateLimiter · Util
    server/
      init.server.luau        -- deterministic service loader (Init → Start)
      Data/        Template · Migrations          Packages/   ProfileStore (vendored, never reformat)
      Services/    Data · Candy · Door · Minigame · Loot · Homeowner (AI) · Case · Inventory · Familiar
                   Shop · Upgrade · Rebirth · SoulShop · Quest · Daily · Playtime · Tutorial · Party · Social
                   WorldEvents (night cycle, Witching Hour, Full-Size Bar, Blood Moon) · Leaderboard
                   Monetization · Codes · Badges · Announce · Analytics · AntiCheat · Admin
      World/       Builder · Street · HouseStyles/{Trailer,Cottage,Suburban,Victorian,Mansion,Haunted}
                   Interiors/ · Props/ · Monsters/ · Items/ (procedural item models) · Lighting
    client/
      init.client.luau
      Controllers/ HUD · Minigames/{TimingBar,KnockRhythm,NerveHold,CostumeLine} · Jumpscare · AmbientScares
                   CaseOpening · Looting (noise meter, crouch, sprint) · Shop · Inventory · Index · Quests · Daily
                   Rebirth · Store · Party · Settings · Notifications · Tutorial (guide arrow) · ZoneLighting
                   Familiars (client-side rendering) · BucketVisual · Camera · Sound · Input (PC/mobile/gamepad)
      UI/          Theme · create() helper · Components/{Button,Panel,ProgressBar,ItemCard,ViewportIcon,Toast,Tabs}
```

### 5.3 Architecture
- Services and Controllers are plain ModuleScripts with `Init()` and `Start()`, loaded in a fixed order. No framework dependency.
- `Net.luau` declares every RemoteEvent/RemoteFunction in one place, with typed payloads. RemoteFunctions are only for request/response UI calls (shop, cases), never server→client.
- The client UI reacts to a replicated player-state snapshot (pushed as a diff on change) so it never polls.
- UI is built in code with the `create()` helper so Claude can edit everything. The user can still tweak the Theme config.

### 5.4 Data schema (ProfileStore, `version` + ordered migrations, never a breaking change without a migration)
```lua
{ version = 1,
  candy = 0, bucket = 0, souls = 0, rebirths = 0,
  upgrades = { bucketTier = 1, sneakers = 0, charm = 0, stealth = 0, luck = 0, flashlight = 0 },
  soulPerks = {}, neighborhoods = { CardboardCourt = true },
  rareCandy = {},                       -- [caseId] = count
  inventory = {},                       -- [uid] = { id, golden, locked, t }
  equipped = { bucketSkin = nil, costume = nil, familiars = {} },
  index = {}, pity = {},                -- pity[caseId] = { sincePink, sinceRed }
  boosts = {},                          -- [boostId] = remaining play-seconds
  consumables = {}, codes = {}, purchases = {},   -- purchases[PurchaseId] = true (receipts)
  daily = { streak = 0, lastDay = 0 }, quests = {}, tutorial = { step = 1, done = false },
  stats = { lifetimeCandy = 0, doors = 0, perfects = 0, bestStreak = 0, loots = 0, caught = 0, escapes = 0, cases = 0, playtime = 0 },
  settings = { music = 0.5, sfx = 1, jumpscare = "Full", reduceFlash = false },
  firstJoin = 0, lastJoin = 0 }
```
Save on leave, on BindToClose, and on autosave (ProfileStore default). Test the data path in Phase 0, including rejoin, two sessions and Studio shutdown.

### 5.5 Security / anti-exploit
- Validate every remote: types, ranges, rate limits (token bucket per player per remote), and proximity (player within 12 studs of the door or loot spot).
- **Mini-games:** the server issues a challenge `{type, difficulty, seed, issuedAt}`. The client returns raw input timestamps relative to the challenge start. The server re-simulates from the seed to grade it, and rejects input faster than humanly possible or later than the timeout. Per-house cooldowns cap what an exploiter can gain. Log statistical outliers (e.g. PERFECT rate > 90% over 50 doors) through `AntiCheat`. **No auto-bans at launch** (only logging and quietly clamping rewards).
- The server is the only source of candy, rolls, prices, detection, noise and inventory changes. Never trust client-sent amounts or IDs without checking them against config.
- Admin commands (`/candy`, `/rebirth`, `/event`, `/resetme`, `/give`) only for `Config.Admins` (the user's UserId). Essential for testing and balancing.

### 5.6 Performance budget
- 60 FPS on mid-range phones. StreamingEnabled with a sensible target radius. Houses use `ModelStreamingMode = Atomic`.
- ≤ ~4K parts per neighborhood. Reuse shapes, and keep PointLights and shadows-casting lights limited.
- Familiars, ambient VFX, flickering lamps, jumpscares and case reels are **client-side only**. Homeowner NPCs only exist while an interior is occupied.
- Test with Local Server and 3 players. Watch the MicroProfiler and memory.

### 5.7 Testing
- **Lune:** Formulas, LootTable (odds over 1M rolls stay within ±0.1%, pity triggers correctly), Format, and economy_sim against the pacing targets.
- **Studio:** Play Solo, Local Server with 2–3 players (party, announcements, Full-Size Bar race), Device Emulator for phone and tablet, gamepad. Zero errors or warnings in Output from our scripts.
- **Data safety tests:** leave mid-purchase, rejoin quickly, rebirth then rejoin, test migrations on an old-shape profile.

---

## 6. Build phases (dated sprint; today is Thu Oct 22)

| Phase | Date | Build | Definition of Done |
|---|---|---|---|
| **0 · Foundation** | Thu 22 | git init, Rokit + Rojo + Lune + StyLua + Selene, project skeleton, loader, Net, Config stubs, Data service (ProfileStore), Admin commands, PROGRESS.md. **User:** publish the place privately and enable Studio API access (section 8) | Studio connects through Rojo. Candy given by admin command survives a rejoin. Lune tests run. Committed. |
| **1 · Core loop** | Fri 23 | World builder (hub + N1 + N2), doors + **Timing Bar**, candy formula, bucket (holdable visual model), overflow, drop-off stash, Candy Box, HUD, Shop (bucket tiers), bus teleporter, gates | ✅ **Checkpoint A:** the user plays 10 min and the knock → stash → upgrade loop already feels good. |
| **2 · Doors come alive** | Sat 24 | Knock Rhythm, Nerve Hold, Costume Line (+ dialogue), house types (Decorated, Trick, Take-One Bowl, Lights Off), jumpscares + ambient scares + settings, Sweet Streak, night cycle, Witching Hour, Full-Size Bar House, per-house cooldowns, preference icons | Every house type and mini-game works on PC and mobile. A jumpscare actually startles a first-time player. |
| **3 · Heists** | Sun 25 | Interiors per style, loot spots, server noise, crouch/sprint, Homeowner AI per neighborhood, caught (−50% bucket) / escape, house lockout, safe-cracking | ✅ **Checkpoint B:** looting feels tense. Two players can co-op a house (one distracts). |
| **4 · Progression** | Mon 26 | Rare candy drops, all cases + **case-opening reel**, ~75 items + procedural models, inventory/equip/Equip Best, familiars (client-rendered), costumes on the character, upgrade tracks, **Rebirth** + Soul Shop, neighborhoods 3–6, rank titles and auras, index (view), economy sim pass #1 | A full first life to rebirth is playable. Sim hits the pacing targets ±20%. |
| **5 · Retention & social** | Tue 27 | Tutorial + guide arrow, daily calendar, playtime gifts, daily quests, party + friend bonus + invite, leaderboards, codes, announcements, settings menu, analytics funnels and economy events | ✅ **Checkpoint C:** feature complete (P0). New-player flow tested from a reset profile. |
| **6 · Money & polish** | Wed 28 | Monetization (passes, products, receipts, PolicyService, Store UI, Starter Pack offer), sound pass with verified IDs, lighting and VFX pass, UI juice pass, gamepad/mobile pass, performance pass, Blood Moon event (time-triggered), economy sim pass #2 | Purchases work in Studio test mode, receipts are idempotent, no Output errors, 60 FPS target met. |
| **7 · Release candidate** | Thu 29 | Friends playtest (private server or Team Test), bug bash, balance from real data, data-safety tests, LAUNCH_CHECKLIST, title, description and thumbnail shots. **User:** create passes/products/badges and paste in the IDs, icon/thumbnails, maturity questionnaire | ✅ **Checkpoint D:** no known blockers. User signs off. |
| **8 · LAUNCH** | **Fri 30** | Go public early in the day (UTC morning/midday, before the US after-school peak). Live monitoring of errors and analytics, hotfix fast | Game is public and stable. |
| **🎃 Halloween** | **Sat 31** | Blood Moon starts automatically at 00:00 UTC. Post codes, watch servers, hotfix | Event live. |

**Phase-order rule:** finish each phase's DoD before starting the next. If a phase slips by more than half a day, cut P1 items immediately and note it in PROGRESS.md.

---

## 7. Scope triage

- **P0 — must ship Oct 30:** everything in phases 0–6 unless marked P1. Minimum 5 neighborhoods if time gets tight (Blackwood can ship Oct 31 as a "Halloween unlock").
- **P1 — if on schedule:** familiar fusion (Golden), index completion rewards, weekly quests, badges, group bonus, hide spots, Smoke Bomb/Decoy, Candy Goblin, cosmetics shop (trails and auras), melt duplicates, BakeWorld snippet.
- **P2 — post-launch updates (weekly):** neighborhood 7+ (Count Sugula's Castle), trading (with anti-scam confirmations), a "Candy Pass" season pass, emotes, personal home plot that visibly fills with your candy, cross-server legendary announcements (MessagingService), Experience Notifications ("your daily reward is ready"), seasonal re-skin after Halloween so traffic doesn't die on Nov 1 (spooky year-round, plus winter/holiday events).

---

## 8. What only the user can do (Claude: prompt for these at the right time, with exact clicks)

| When | Task |
|---|---|
| Phase 0 | Open Studio → open/create the place → **File → Publish to Roblox** (private) → Game Settings → Security → **Enable Studio Access to API Services**. Install the Rojo plugin (Claude can run `rojo plugin install`). Give Claude your Roblox **UserId** (for admin commands). |
| Phase 0 (optional) | Approve installing the Roblox Studio MCP server. |
| Phase 6 | Creator Hub → your experience → **Monetization**: create the gamepasses and developer products (names, prices, icons) and paste the IDs to Claude. Optional: create badges and a Roblox group. |
| Phase 7 | Upload an icon and 3–5 thumbnails (Claude helps stage shots), fill in the **Maturity & Compliance questionnaire**, set genre, devices (PC, phone, tablet, console), server size 12, private-server price. Turn on **automatic translation** in Localization (free global reach). Get 2–4 friends to playtest. Check your account meets Roblox's current requirements for making an experience public, *a day early*. |
| Phase 8 | Flip the experience to **Public**. Optional: post jumpscare clips (TikTok/Shorts), set up a small Ads Manager campaign. |

---

## 9. Decisions made on the user's behalf (change any of them anytime)
- Bucket fills → stash. Candy Box full → Rebirth (the user delegated this; it's the strongest version of both loops).
- Caught penalty = 50% of **carried** candy. Banked candy is always safe.
- Always night, 18-minute Nights, Witching Hour finale.
- Procedural art first, swap-in models later.
- Robux monetization included (section 3.17); the user approves prices.
- Server size 12, party max 4. English at launch with auto-translation.
- Working title **"Trick or Treat with Friends 🎃"** (alternatives to pick from in Phase 7: "Trick or Treat Simulator", "Candy Heist 🍬", "Knock Knock: Trick or Treat").

## 10. Questions Claude will ask at the right moment (don't block on them now)
- Phase 0: your Roblox UserId. Should we use a GitHub repo for backup?
- Phase 6: approve the Robux prices. Do you have a Roblox group?
- Phase 7: final game name, your timezone (to time the launch), who's playtesting on Oct 29.
