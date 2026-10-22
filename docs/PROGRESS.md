# PROGRESS — Trick or Treat with Friends

> Read PROMPT.md first, then this file. Update this file at the end of every phase.
> Deadline: **public Fri 2026-10-30**, Blood Moon event Sat Oct 31.

## Status

| Phase | Status | Date |
|---|---|---|
| 0 · Foundation | ✅ done, verified in Studio through the MCP | 2026-10-22 |
| 1 · Core loop | 🔨 loop playable and verified in Studio; quality pass (UI, models, sounds) requested by the user | target Fri Oct 23 |
| 2–8 | not started | see PROMPT.md §6 |

## How to work on this project

- Tools are installed by Rokit at `%USERPROFILE%\.rokit\bin` (versions pinned in `rokit.toml`). Run them by full path if they aren't on PATH yet: `rojo`, `lune`, `stylua`, `selene`.
- **Live sync:** `rojo serve` (port 34872) → in Studio: Plugins → Rojo → Connect.
- **Checks before every commit:** `stylua src tests` · `selene src` · `lune run tests/run` · `rojo build -o build/TorT.rbxlx`.
- **Studio MCP:** `.mcp.json` registers `Roblox_Studio` (Roblox's built-in Studio MCP via `%LOCALAPPDATA%\Roblox\mcp.bat`). It needs Studio → Assistant → … → Manage MCP Servers → *Enable Studio as MCP server*, and a fresh Claude session. Its tools include execute_luau, start_stop_play, get_console_output, screen_capture, search_asset and insert_asset. Every call needs a `studio_id` from `list_roblox_studios`.
- **Admin chat commands** (anyone in Studio, owner UserId 4710305538 live): `/admin` (list) · `/candy 5k` · `/setcandy` · `/bucket` · `/souls` · `/setrebirths` · `/data [key]` · `/reset` · `/save`. Optional last argument = player name. `/help` is Roblox's built-in, so the list command is `/admin`.
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
- Economy changes vs PROMPT (all logged in docs/ECONOMY.md): candy per door ×~2, Maple Lane 150, door cooldown 90 s, 3 drop-offs per street, Charm/Sneakers cost growth lowered so every price ≤ 50% of the box.

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

## Next up

1. **Quality pass requested by the user** ("10× better: UI, models, sounds"): art direction for models, a juicier UI, more sounds and music.
2. Checkpoint A: the user plays 10 minutes from a fresh profile (the test profile was reset).
