# PROGRESS — Trick or Treat with Friends

> Read PROMPT.md first, then this file. Update this file at the end of every phase.
> Deadline: **public Fri 2026-10-30**, Blood Moon event Sat Oct 31.

## Status

| Phase | Status | Date |
|---|---|---|
| 0 · Foundation | ✅ done, verified in Studio through the MCP | 2026-10-22 |
| 1 · Core loop | ✅ code done and verified in Studio. Waiting on the user's 10-minute Checkpoint A | 2026-10-22 |
| 2 · Doors come alive | ✅ code done and verified in Studio (see "Phase 2 status"). Ambient scares are deferred to Phase 4 (they're N3+ and N3 isn't built yet) | 2026-10-22 |
| 3 · Heists | ⏭ next | target Sun Oct 25 |
| 4–8 | not started | see PROMPT.md §6 |

## How to work on this project

- Tools are installed by Rokit at `%USERPROFILE%\.rokit\bin` (versions pinned in `rokit.toml`). Run them by full path if they aren't on PATH yet: `rojo`, `lune`, `stylua`, `selene`.
- **Live sync:** `rojo serve` (port 34872) → in Studio: Plugins → Rojo → Connect.
- **Checks before every commit:** `stylua src tests` · `selene src` · `lune run tests/run` · `rojo build -o build/TorT.rbxlx`.
- **Studio MCP:** `.mcp.json` registers `Roblox_Studio` (Roblox's built-in Studio MCP via `%LOCALAPPDATA%\Roblox\mcp.bat`). It needs Studio → Assistant → … → Manage MCP Servers → *Enable Studio as MCP server*, and a fresh Claude session. Its tools include execute_luau, start_stop_play, get_console_output, screen_capture, search_asset and insert_asset. Every call needs a `studio_id` from `list_roblox_studios`.
- **Admin chat commands** (anyone in Studio, owner UserId 4710305538 live): `/admin` (list) · `/candy 5k` · `/setcandy` · `/bucket` · `/souls` · `/setrebirths` · `/unlock <id|all>` · `/upgrade <track> <level>` · `/event dawn|witching|fullsize|bloodmoon on/off/auto` · `/housetype <type>` (nearest house) · `/data [key]` · `/reset` · `/save`. Optional last argument = player name. `/help` is Roblox's built-in, so the list command is `/admin`.
- **Testing a mini-game screen from the MCP:** fire `Remotes.MinigameStart` at the client with a fake challenge, e.g. `{ id = -1, kind = "CostumeLine", difficulty = 5, seed = 7, context = { personality = "WitchyWanda" } }`. The server ignores the submission for an unknown id.
- **From the Studio MCP / command bar** (play mode, Server datamodel): `game.ServerStorage.DevBridge:Invoke("/candy 5k")` runs a command as the first player, and `DevBridge:Invoke("data")` returns a copy of their data. `require()` from the MCP gets a *separate* module instance with no live profiles, so always go through the bridge.

## Architecture decisions (Phase 0)

- Folder layout: `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server (Script), `src/client` → StarterPlayerScripts.Client (LocalScript). The project file only claims those three instances, so anything built by hand in Studio (Workspace etc.) is left alone.
- `Loader.run(folder, order, label)`: explicit load order. Modules not in the list are warned about and skipped. Each module has `Init` (sync) then `Start` (spawned).
- `Net`: every remote is declared in `src/shared/Modules/Net.luau`. The server creates them in `Net.setup()`. `Net.connect` / `Net.handle` add per-player token-bucket rate limits plus pcall. Handlers must still validate their arguments.
- **Data:** ProfileStore (vendored from MadStudioRoblox/ProfileStore commit 45c9847, Apache-2.0; `.styluaignore` keeps it byte-identical). Store `PlayerData_v1`, key `Player_<UserId>`. `Migrations.apply` runs before `Reconcile`. Data saved by a *newer* server ("future") causes a kick without touching the data.
- **Writing data:** only through `DataService.set / increment / mutate / markDirty`. Dirty top-level keys are batched to the client every 0.15 s through `StateSync`. The client keeps a read-only copy in `StateController` (`observe(key, fn)`).
- `stats.playtime` is accumulated server-side and not synced each tick.
- `purchases` is an array of recent PurchaseIds (it will be capped in Phase 6) instead of a map.
- Lune tests load Roblox-style modules through `tests/lib/rbx.luau` (emulates `script`, instance `require`, and `game:GetService` for ReplicatedStorage/ServerScriptService). Keep pure logic in modules that only require through those paths.
- `DebugController` was removed when the Phase 1 HUD landed.

## Architecture decisions (Phase 1)

- **World** is built at server start by `Server/World/Builder` from `Config/Neighborhoods` + `Config/World` (seeded, identical every boot): hub → gate → street → gate… Streets bend by `turn` degrees. Only `enabled` neighborhoods are built; the first disabled one gets a "COMING SOON" gate and a dead end. ~2.5K parts for hub + 2 streets.
- Swap-in: `ReplicatedStorage.Assets.Houses.<Style>` (needs a part named Door) and `ReplicatedStorage.Assets.Buckets.<Model>` (needs Handle) replace procedural models; `Workspace.Handmade.<NeighborhoodId>` replaces a street's houses (every part named Door becomes a house).
- Edit-mode preview: `require(game.ServerScriptService.Server.World.Builder).build(workspace)` from the command bar (delete Workspace.World afterwards). The runtime also deletes the template Baseplate/SpawnLocation (play session only).
- **Doors**: server `DoorService` handles the ProximityPrompt → `MinigameService.issue` (seeded challenge) → client plays → submits raw tap times → server re-grades with the shared `Modules/Minigames/TimingBar` → `Formulas.doorCandy` → `CandyService.addToBucket`. Cooldowns use `workspace:GetServerTimeNow()` so the client can show the 💤 timer. Invalid input grades as MISS and is logged; >90% PERFECT over 50 doors is logged (no bans).
- **Candy** only moves through `CandyService` (addToBucket, stash, spend). `StashService` polls positions every 0.2 s against the drop-off list (no Touched events).
- **Gates**: barrier collision is turned off *client-side* for owners; `NeighborhoodService` polls zones every 0.3 s, sets the `Zone` player attribute (drives client lighting blends) and teleports anyone deep inside a street they don't own back to its gate.
- **Bucket on the character**: `Shared/Models/Buckets` builds one model per tier with a mount type (hand / back / tow / float) and candy pieces that appear as it fills; `BucketService` welds it on and updates the fill.
- Client UI is code-built: `UI/Components/{Button,Panel,ProgressBar}`, `UI/Scale` (UIScale from a 1100×620 reference, clamped 0.6–1.15). One Panel open at a time.
- Sounds: `Config/Sounds` (verified IDs from DailySoundsFX and ProSoundEffects, load-tested), `SoundController.play(name)`.
- Admin additions: `/unlock <id|all>`, `/upgrade <track> <level>`; `ServerStorage.DevBridge` for the MCP.
- **AI meshes (user's choice, 2026-10-22):** models are generated in Studio with the MCP `generate_mesh` tool (assets land on the owner's account), then their MeshId/TextureID go into `Config/Meshes`. `Modules/MeshLibrary` builds them on the server at boot with `AssetService:CreateMeshPartAsync` and clones them; anything that fails to load falls back to the part-built version. Nothing depends on saving the place file. A freshly generated mesh can fail to load in the *first* play session after generation (it works in the next one).
- First AI mesh: the Plastic Pumpkin bucket (tier 2). The procedural block version stays as the fallback.
- Economy changes vs PROMPT (all logged in docs/ECONOMY.md): candy per door ×~2, Maple Lane 150, door cooldown 90 s, 3 drop-offs per street, Charm/Sneakers cost growth lowered so every price ≤ 50% of the box.

## Architecture decisions (Phase 2)

- **WorldEventsService** owns the Night cycle (18 min, 6 PM → midnight), Witching Hour (last 3 min: ×2 candy, +1 difficulty, more trick houses, red fog, music swap, 60 s warning), Dawn (house reroll + cooldown reset), Full-Size Bar houses (every ~4 min on a street someone is on, ×10 for the first 6, 60 s) and the Blood Moon (Config/Events timestamps, Oct 31 00:00 → Nov 1 08:00 UTC, ×2). State is replicated as attributes on `ReplicatedStorage.WorldState`, and the clients draw the clock, banners and beam from it.
- **HouseService** rolls each house's type (Config/HouseTypes weights per tier), homeowner personality and preference at every Dawn. These become attributes on the house model (`HouseType`, `Owner`, `Preference`). Bowl houses get a bowl with Take one / hold-3 s TAKE ALL prompts (35% caught → lose 50% of the bucket). Lights-off and bowl houses don't answer the door.
- **Mini-games** share one interface: `Modules/Minigames/<Kind>.luau` exposes `generate(seed, difficulty, context)`, `grade(spec, input)` and `validInput(spec, input, elapsed)`, and the client UI in `Controllers/Minigames/<Kind>.luau` returns a session with `press` / `release` / `cancel`. Kinds: TimingBar, KnockRhythm (repeat the knock pattern, graded by average timing error), NerveHold (hold through scares, graded by share held, fake "LET GO!" traps from difficulty 5), CostumeLine (pick the answer the homeowner's personality likes; 5 personalities, 50 lines in Config/Dialogue). Trick houses always roll NerveHold, and every NerveHold ends in a jumpscare.
- **Door candy** now includes house type (Decorated ×1.5, Trick ×2.5 if brave), Sweet Streak (+10% per consecutive GREAT/PERFECT, max +100%, a MISS resets it), Full-Size ×10 and the event multiplier (capped at ×4).
- **Jumpscares** are client-side (`JumpscareController`): the camera locks onto the door, the door swings open, and the AI **Ghost** mesh lunges at the camera with a stinger, shake and red flash. Settings: Full / Reduced / Off ("BOO!"). A 45 s global cooldown downgrades back-to-back scares.
- `MeshLibrary` now parks its templates in `ReplicatedStorage.MeshTemplates` so the client can clone them too.
- **Audio**: `SoundGroup`s "SFX" and "Music" carry the volume settings. `MusicController` crossfades zone tracks, the Witching Hour theme and the Blood Moon theme (Config/Music, DistrokidOfficial licensed tracks, load-tested).
- **Settings** panel (⚙ on the HUD): music and SFX volume, jumpscare intensity, reduce flashing. Saved through the validated `SaveSettings` remote.
- HUD additions: Night clock panel (Witching countdown, Blood Moon), Sweet Streak pill, and callouts (BRAVE!, FULL-SIZE ×10, TAKE ALL, CAUGHT!).
- AI mesh generation: the goblin homeowner prompt was rejected by Roblox moderation, so the Ghost is the only monster for now.

## Phase 0 checkpoint (verified 2026-10-22 through the Studio MCP)

All passed: Rojo connected, `[Server] 4 modules ready`, `[Data] Loaded`, `[Data] DataStore access OK`, `/candy` typed in chat updates the data, readout, leaderstats and toast, the candy survives stop → play, and `/reset` works. Manual version for the user:

1. Studio → **Plugins** tab → **Rojo** → **Connect**. If there's no Rojo button, restart Studio once.
2. In the Explorer you should see `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client`.
3. Press **Play**. In Output: `[Server] 4 modules ready`, `[Data] Loaded <you>`, `[Data] DataStore access OK`. The bottom-left readout shows `🍬 0`.
4. In chat type `/candy 5k`. A green toast appears, the readout and player list show 5K.
5. Stop and press Play again. Candy is still 5K (the data saved).
6. `/reset` brings it back to 0.

## Known issues / to verify

- [x] `TextChatCommand.Triggered` fires server-side for the admin commands (tested by typing `/candy 1k` in chat).
- [x] The place is published (PlaceId 89535503147537) and Studio API access is on.
- `ContentId rbxassetid://203785492 failed: Asset type does not match` shows in Output on play. It isn't referenced by anything in the readable DataModel, so it's Roblox core/avatar content, not our scripts. Ignore it.

## Phase 1 status (2026-10-22)

Verified in Studio through the MCP: world builds (32 houses, 7 drop-offs), knock → Timing Bar → candy pop into the bucket, overflow warning, 💤 cooldown, stash at the Candy Box, shop purchases (bucket model swaps, Sneakers changes WalkSpeed), Maple Lane gate unlock + celebration banner, pushback from locked streets, bus travel with fade. No errors from our scripts in Output. 45 Lune tests pass.

## Phase 2 status (2026-10-22)

Verified in Studio through the MCP: house types roll at boot (e.g. Cardboard Court: 7 Normal, 4 Decorated, 3 Bowl, 2 Lights Off), house badges, bowl with a sign, string lights on decorated houses, a Trick house's Nerve Hold (whisper lure, bravery bar, ×2.5 BRAVE payout), the jumpscare (client monitor: camera locked ~1.3 s, ghost spawned; the screenshot tool couldn't capture that moment), the Knock Rhythm and Costume Line screens, the Witching Hour (red fog, clock → 11 PM, ×2 banner) and the Full-Size Bar gold beam. No errors from our scripts. 55 Lune tests pass. The test profile was reset afterwards.

**Phase 2 user test (5 min):** Play → walk into Cardboard Court and look at the badges over the doors (owner + preference icon). Try a 🍬 bowl house: **E** = take one, hold **F** = TAKE ALL (risky!). In chat: `/housetype Trick` next to a door, knock, and **hold Space** through the scares (jumpscare at the end). `/event witching` turns everything red with ×2 candy, and `/event fullsize` spawns a gold-beam house. ⚙ Settings → Jumpscares Reduced/Off.

## Next up

0. **Phase 3 · Heists** (PROMPT §3.9): interiors per style, loot spots, server-side noise, crouch/sprint, Homeowner AI, caught/escape, house lockout, safe-cracking.
1. The user asked for proof that real models are possible, then to continue with the plan ("give me one high quality model … and continue with the prompt"). Done (the pumpkin bucket). **From now on every feature ships with real art, juicy UI and sound** (see the memory note). The remaining 11 bucket tiers, houses and props get AI meshes as each phase touches them.
2. **Checkpoint A** (user, 10 min, fresh profile; the test profile was reset): Studio → Play →
   1. walk through the CARDBOARD COURT arch, press **E** at a door, stop the needle in the green (Space/click/tap) → candy flies into the bucket;
   2. fill the bucket (see OVERFLOW), stand in a glowing **Candy Box** circle to stash;
   3. **Shop**: buy the Plastic Pumpkin (AI mesh in your hand), Charm, Sneakers;
   4. reach 150 → unlock **Maple Lane** at the gate at the end of the street; try a 🚌 bus stop;
   5. report anything that feels slow, ugly or confusing.
   Phase 2 started in parallel (the user said to continue).
