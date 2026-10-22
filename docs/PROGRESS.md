# PROGRESS — Trick or Treat with Friends

> Read PROMPT.md first, then this file. Update this file at the end of every phase.
> Deadline: **public Fri 2026-10-30**, Blood Moon event Sat Oct 31.

## Status

| Phase | Status | Date |
|---|---|---|
| 0 · Foundation | ✅ done, verified in Studio through the MCP | 2026-10-22 |
| 1 · Core loop | 🔨 in progress | target Fri Oct 23 |
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
- `DebugController` (bottom-left readout) is **temporary**. Delete it when the Phase 1 HUD lands.

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

## Next up (Phase 1)

World builder (hub, Cardboard Court, Maple Lane), doors + Timing Bar, candy formula (`Formulas.luau` + spec), bucket model and overflow, stash and Candy Box, HUD, bucket shop, bus teleporter, gates.
