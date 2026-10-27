# PROGRESS — Trick or Treat with Friends

> Read PROMPT.md first, then this file. Update this file at the end of every phase.
> Deadline: **public Fri 2026-10-30**, Blood Moon event Sat Oct 31.

## Status

| Phase | Status | Date |
|---|---|---|
| 0 · Foundation | ✅ done, verified in Studio through the MCP | 2026-10-22 |
| 1 · Core loop | ✅ code done and verified in Studio. Waiting on the user's 10-minute Checkpoint A | 2026-10-22 |
| 2 · Doors come alive | ✅ code done and verified in Studio (see "Phase 2 status"). Ambient scares are deferred to Phase 4 (they're N3+ and N3 isn't built yet) | 2026-10-22 |
| **V2 pivot** (PROMPT §V2) | 🔨 in progress: AI houses, first person, PSX camera, minimal HUD + radial menu, homeowners in doorways, own character models (4 kids + 6 costumes, wardrobe) done. Next: separate maps + bus + souls, crates, lobby/runs, lives/death, more costumes (target 30+) | 2026-10-22 |
| 3 · Maps & heists | after the pivot (see PROMPT §V2.4) | Oct 24–25 |
| 4–8 | see PROMPT §V2.4 | |

## How to work on this project

- Tools are installed by Rokit at `%USERPROFILE%\.rokit\bin` (versions pinned in `rokit.toml`). Run them by full path if they aren't on PATH yet: `rojo`, `lune`, `stylua`, `selene`.
- **Live sync:** `rojo serve` (port 34872) → in Studio: Plugins → Rojo → Connect.
- **Checks before every commit:** `stylua src tests` · `selene src` · `lune run tests/run` · `rojo build -o build/TorT.rbxlx`.
- **Studio MCP:** `.mcp.json` registers `Roblox_Studio` (Roblox's built-in Studio MCP via `%LOCALAPPDATA%\Roblox\mcp.bat`). It needs Studio → Assistant → … → Manage MCP Servers → *Enable Studio as MCP server*, and a fresh Claude session. Its tools include execute_luau, start_stop_play, get_console_output, screen_capture, search_asset and insert_asset. Every call needs a `studio_id` from `list_roblox_studios`.
- **Admin chat commands** (anyone in Studio, owner UserId 4710305538 live): `/admin` (list) · `/candy 5k` · `/setcandy` · `/bucket` · `/souls` · `/setrebirths` · `/unlock <id|all>` · `/upgrade <track> <level>` · `/event calm|witching|fullsize|bloodmoon on/off/auto` · `/faint` · `/hurt [amount]` · `/heal` · `/item <id|all> [count]` · `/housetype <type>` (incl. `Seller`) (nearest house) · `/knifer [away|info]` · `/chase [home]` (the nearest house's homeowner after you) · `/data [key]` · `/reset` · `/save`. Optional last argument = player name. `/help` is Roblox's built-in, so the list command is `/admin`.
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
- **HouseService** rolls each house's type (Config/HouseTypes weights per tier), homeowner personality and preference at every Dawn. These become attributes on the house model (`HouseType`, `Owner`, `Preference`). Bowl houses get a bowl with Take one / hold-3 s TAKE ALL prompts (35% caught → lose 50% of the bucket). *(Reworked 2026-10-26: take-all only, a burst lamp and a chasing homeowner; see "Candy bowl rework".)* Lights-off and bowl houses don't answer the door.
- **Mini-games** share one interface: `Modules/Minigames/<Kind>.luau` exposes `generate(seed, difficulty, context)`, `grade(spec, input)` and `validInput(spec, input, elapsed)`, and the client UI in `Controllers/Minigames/<Kind>.luau` returns a session with `press` / `release` / `cancel`. Kinds: TimingBar, KnockRhythm (repeat the knock pattern, graded by average timing error), NerveHold (hold through scares, graded by share held, fake "LET GO!" traps from difficulty 5), CostumeLine (pick the answer the homeowner's personality likes; 5 personalities, 50 lines in Config/Dialogue). Trick houses always roll NerveHold, and every NerveHold ends in a jumpscare.
- **Door candy** now includes house type (Decorated ×1.5, Trick ×2.5 if brave), Sweet Streak (+10% per consecutive GREAT/PERFECT, max +100%, a MISS resets it), Full-Size ×10 and the event multiplier (capped at ×4).
- **Jumpscares** are client-side (`JumpscareController`): the camera locks onto the door, the door swings open, and the AI **Ghost** mesh lunges at the camera with a stinger, shake and red flash. Settings: Full / Reduced / Off ("BOO!"). A 45 s global cooldown downgrades back-to-back scares.
- `MeshLibrary` now parks its templates in `ReplicatedStorage.MeshTemplates` so the client can clone them too.
- **Audio**: `SoundGroup`s "SFX" and "Music" carry the volume settings. `MusicController` crossfades zone tracks, the Witching Hour theme and the Blood Moon theme (Config/Music, DistrokidOfficial licensed tracks, load-tested).
- **Settings** panel (⚙ on the HUD): music and SFX volume, jumpscare intensity, reduce flashing (later: PSX effects, head bob). Saved through the validated `SaveSettings` remote.
- HUD additions: Night clock panel (Witching countdown, Blood Moon), Sweet Streak pill, and callouts (BRAVE!, FULL-SIZE ×10, TAKE ALL, CAUGHT!).
- AI mesh generation: the goblin homeowner prompt was rejected by Roblox moderation, so the Ghost is the only monster for now.

## V2 pivot (2026-10-22 evening) — the user's new direction is PROMPT §V2

- **Houses:** 18 AI meshes (3 per neighbourhood, scarier each street) in `Config/Meshes` + `Config/HouseModels`. Each run rolls a random model per lot (`Street.meshHouse`); an invisible `Door` part at the front-centre is the knock zone, plus a `PorchLight`. Meshes wider than 34 studs are scaled down to fit the lots. Server boot now waits for the meshes (~4–9 s on a fresh server); characters spawn only after the world is built (`CharacterAutoLoads = false`, `CharacterService`), behind a client loading screen.
- **Generating meshes:** only in Studio **edit** mode (in play mode the job fails with "Model generation should only be called from the server"). Darker wording ("desaturated, no bright colors") avoids toy-like results. A goblin prompt with "angry face… arms stretched" was rejected by moderation.
- **First person** for everyone (`LockFirstPerson`), `CameraController` (PSX grade, blur, vignette, head-bob and handheld sway; grain is off until a seamless noise texture is found), `ViewmodelController` (a local copy of your bucket in view, candy mirrored). Settings → "PSX effects".
- **Theme** is now minimal noir (near-black translucent tiles, hairline borders, SpecialElite typewriter headings, BuilderSans HUD). **HUD**: bottom-left chips (candy, bag + bar, lives, souls, clock), next-goal line, streak chip, crosshair dot, `[TAB] MENU` hint. **Radial menu** (`RadialMenuController.register`): Tab/Q/DPad-Up/MENU button; Shop = "UPGRADES", Settings. Windows use a `Modal` button to free the mouse in first person. Roblox's player list, backpack and health bar are hidden.
- **Homeowners:** 5 uncanny AI figures (`Config/Homeowners.ROSTER`), rolled per house at Dawn with random stretch/scale/tilt (`HomeownerService.roll`). They slide out of the doorway when someone knocks, twitch while the mini-game runs, and go back inside after (server-side, so friends see them). The jumpscare uses the house's own homeowner (ghost fallback).
- **Lives** are in player data (`lives`, `livesRefillAt`, `Config/Lives`) and on the HUD. Death comes with interiors (Phase 3). *(Replaced 2026-10-26 by 100 health, `HealthService`; see "Feedback round 2".)*
- UI icons: `Config/Images` (image ids resolved from Creator Store decals via `InsertService:LoadAsset` in edit mode).
- **Characters (no Roblox avatars, user's call):** every starter kid and costume is its own AI character (`Config/Characters`), generated with `segmentation = explicit` into head/torso/left arm/right arm/left leg/right leg. `Modules/CharacterRig` turns the six segments into a Humanoid rig: R6 part names so "Torso"/"Right Arm" lookups keep working, Motor6Ds at neck/shoulders/hips, an R15-type Humanoid whose HipHeight puts any proportions on the ground, and a root box from hips to eyes. `CharacterAnimController` animates every rig on every client: stiff PSX swing at 14 pose-fps, idle breathing, a slightly wrong head sway, arms up in the air. `CharacterService` builds the rig and assigns `player.Character` itself, and swaps it in place when you change costume or kid (`CameraController` re-targets the camera; Roblox only does that for characters it spawned).
  - 4 starter kids (Milo, Ivy, Theo, Nell); a new player gets a random one, switchable in the wardrobe.
  - 6 costumes: Sheet Ghost 10, Pumpkin Head 60, Little Witch 180, Black Cat 450, Skeleton 1.5K, Vampire 6K. Each gives +5–14% candy; a tag matching the homeowner's preference gives +40%. No costume = ×0.15 door candy (`CandyService.bonuses`).
  - Wardrobe (`CostumeController`, radial "COSTUMES"): a turning 3D preview, cards with ViewportFrames, Costumes / Your Kid tabs. Remotes: `BuyCostume`, `EquipCostume`, `ChooseStarter`. Data: `costumes`, `starter`, `equipped.costume`.
  - **Generating characters:** generated meshes face +Z (the parts come rotated 180°) and the left/right labels are unreliable, so the config is extracted by position and rotated to face -Z: run `tools/extract_character.luau` in edit mode with the model selected. Ask for "arms hanging straight down… stylized 1999 PlayStation game character, smooth low poly, not blocky, not voxel" (the first vampire came out Minecraft-like). More than ~3–4 jobs at once fails with "Too Many Requests". Freshly published meshes and textures can render blank in Studio for a few minutes.
  - Mesh loading is split into groups: the world builds once the "World" meshes are in (server boot ~3.5 s), and characters spawn once the "Characters" group is in.
- **Homeowners (2026-10-23):** built and animated on every client (`HomeownerController`); the server only sets house attributes (`OwnerModel`, `OwnerSeed`, `OwnerOut`, `OwnerStyle`). Pools per neighbourhood (`Config/Homeowners`), 6 new rigged owners in `Config/Characters` (`Owner_*`) plus the 5 old one-piece statues. Per-house body morphs from the seed (`CharacterRig` "puppet" mode + `Morph`: stretch, long arms, wrong-sized head, thin), scarier per neighbourhood (`CREEP`). Five entrances (Creep, Snap, Peek, Waiting, Blackout), then idle: head tracks you, breathing, twitches, some slowly reach for you; tall ones duck under the door frame. The jumpscare reuses the doorway figure. The loading screen preloads every mesh and texture (`ContentProvider:PreloadAsync`), which fixes half-loaded homeowners.
- **Houses are modelled in Blender now (user rejected AI-mesh and part-built houses).** `art/scripts/victorian.py` builds the Victorian (tower, gabled bay, wraparound porch, real cut-outs for doors and windows, turned posts, damage) from CC0 Poly Haven textures (`art/scripts/fetch_textures.sh`); `art/scripts/export_victorian.py` bakes one 1024 atlas per mesh group (colour with grime/AO, normal, roughness) and exports `art/export/victorian/Victorian.fbx` (`-- --only FrontDoor,BackDoor` re-bakes just those). The user imports it with File → Import 3D; `tools/setup_victorian.luau` (MCP/command bar) turns it into `ReplicatedStorage.Assets.Houses.Victorian`: pivot, hinged doors, invisible knock "Door", lights, glass, invisible collision. **Save the place after** (Assets aren't in Rojo). Street uses it on every Cardboard Court lot (`Neighborhoods` style = "Victorian"; `HouseModels` has no meshes for it) and `Victorian.dressLot` adds the yard and the window rooms. A house is ~45 parts; the whole world dropped from ~16k to ~3.5k parts. `World/HouseStyles/Victorian.luau` (the part-built version) stays as the fallback when the asset is missing.
  - **Every model is made in Blender from now on (user's rule, 2026-10-23).** Same pipeline for each: a script in `art/scripts/`, CC0 textures, `export_victorian.export()` to bake and write the FBX, the user imports, a `tools/setup_*.luau` files it under `ReplicatedStorage.Assets`.
  - House polish: gutters and downspouts (the back one torn loose), a fascia and gutter on the porch roof, stone back steps with a handrail and a hood over the back door, iron cresting on the ridge, dead vines up the bay corner, the tower and two porch posts, jack-o'-lanterns with candles (`PumpkinLight`), a rotten pumpkin, an iron urn of dead stalks. Glass is SmoothPlastic (Roblox's Glass material hides what's behind it).
  - **Yard set** (`art/scripts/yard.py` → `art/export/yard/Yard.fbx`, `tools/setup_yard.luau` → `Assets.Yard`): wrought-iron fence panel (stretched per lot to fit) and posts with finials, stone gate pillars, an arched double gate (two `GateLeaf`s sharing a `Group`, so one prompt swings both; a single leaf couldn't clear the steps in the 3-stud-deep yard), two dead trees, a rusty mailbox, a cracked R.I.P. headstone and a stone cross, stepping stones. `dressLot` uses it when `Assets.Yard` has every piece, else the built yard; invisible blockers do the colliding. Verified in play (2026-10-23): walk sidewalk → gate → steps → porch, the fence and graves block, the closed gate blocks. Prompts never show in an MCP-driven play session, so pressing E on the gate is a manual check. Bake brightness: check `<name>_color.png` medians against the house's (Stone ≈ 38); Blender preview lights hide a too-dark bake.
  - **Rooms behind the windows (2026-10-23, replaced the flat room pictures):** `art/scripts/interiors.py` builds real rooms into the house mesh: parlour with fireplace (bay), nursery with crib and a doll in a rocking chair, kitchen behind the back door, bedrooms, dining room, a dust-sheeted room, study, stair hall with a doorway into darkness, a boarded-up junk room, an octagonal room on each tower floor and the attic. Procedural wallpapers (green stripes, burgundy damask, mustard sprigs) with stains and peeling, floorboards, plaster ceilings with a lamp shade, skirting, pleated velvet drapes. It also writes `World/HouseData/VictorianRooms.luau` (lamp positions, room boxes; generated, don't edit). `Victorian.roomLights` lights 2-4 rooms per house (+ the attic 40%): a Neon `RoomBulb` and a shadowed PointLight; keeps at most one `Figure_<room>` (nursery window, tower top, stair hall), usually in a lit room. Lights Off houses darken the bulbs.
- **Two more Blender houses (2026-10-23):** `art/scripts/farmhouse.py` (Maple Lane: a rotting Carpenter Gothic farmhouse, board-and-batten, steep Gothic gable with a pointed window, rusted tin roof, sagging porch, lean-to kitchen, fieldstone chimney, rooster weathervane) and `art/scripts/mansard.py` (Cardboard Court: a Second Empire mansion in stained stucco, slate mansard with dormers, a central tower with an oculus and its own mansard cap, iron cresting, quoins, bracketed cornices, a columned portico with a balcony). Both have real rooms behind every window and figures. They share `art/scripts/housekit.py`, which also writes `World/HouseData/<Style>.luau` (front door, hinged doors, colliders, lights, decoration anchors, rooms, yard). `tools/setup_house.luau` (set STYLE) turns an import into `Assets.Houses.<Style>` from that data; `World/BlenderLot` dresses any Blender house's lot from it (iron or picket fence, double gate, path, tree, mailbox, graves, room lights; the Victorian uses it too). Cardboard Court alternates Victorian/Mansard like a checkerboard (`Neighborhoods.styles`); Maple Lane's style is `Farmhouse` (its AI cottages stay until the model is imported). The yard set gained a rotten picket fence (PicketPanel/Post/Gate). Street and hub trees (`Props.tree`, dead/autumn kinds) use the Blender dead trees from the yard set when it's imported. Verified in play: 8 Victorian + 8 Mansard on Cardboard Court, 16 farmhouses on Maple Lane, walk gate → steps → door on both new houses.
- **Furniture per house (2026-10-24, the user asked for interior variations; replaces the furniture baked into the houses):** `art/scripts/furniture.py` builds 35 pieces at one origin, each one mesh with its own 512 atlas (`export_victorian.bake` now bakes multi-material objects into one atlas): the old interiors.py furniture plus a coffin on trestles, an upright piano, a seance table, a trunk, a birdcage, floor candles, toy blocks, dust-sheeted shapes and the Figure. `tools/setup_furniture.luau` files `Furniture.fbx` under `Assets.Furniture` (pivot on the shared origin, found from the rug). The houses keep only their walls, lamps, curtains and the hall stairs; their data files list every room's box, role (living/kitchen/hall/tower/attic) and front (window wall). `Config/RoomLayouts` has 20 layouts (parlour, bedroom, nursery, study, dining, seance, coffin wake, piano, dust sheets, watcher chair, aviary, reading nook, sickroom, rocker, portrait gallery, kitchen, scullery, lumber room, forgotten room, candlelit) with size limits; `BlenderLot.furnish` picks one per room per house (rarely the same twice in a house), mirrors it half the time, nudges pieces, keeps them inside the walls and off each other (skips what won't fit, cuts rugs to size), and stands at most one Figure behind a front window (rooms 8+ studs high). **Cardboard Court now mixes all three Blender houses** (Victorian, Mansard, Farmhouse; `Neighborhoods.styles`); Maple Lane is back to its cottages. Fixed on the way: the wardrobe's knobs floated in front of it under the floor (a lathe offset went through its rotation).
- **Decorations (Decorated houses):** `art/scripts/decor.py` → `art/export/decor/Decor.fbx`, `tools/setup_decor.luau` → `Assets.Decor`: a garland of C7 bulbs (three bulb meshes, Neon orange/purple/green) and a pile of pumpkins round a carved, glowing jack-o'-lantern (candle light named `PumpkinLight`, so it flickers). The Victorian template carries `DecorAnchors` (attachments named after the piece: five garlands under the porch beam, the pile on the lawn by the steps); `HouseVisualController` hangs the pieces there and falls back to the old neon balls for houses without anchors. Streets whose houses dress their own lots skip the part-built street pumpkins.
- **Blender pipeline gotcha:** meshes made from curves (vines, branches, stems) bring their own `UVMap`; Roblox reads the first UV map, so `merge_group` drops stray ones before adding Tile/Atlas (they had turned the decor pumpkins glossy black and the trees and vines too dark).
- **Doors that open:** models tagged `Hinged` (Kind, OpenAngle, Openable, Open). `HingeService` toggles Openable ones via their prompt (auto-close 30 s); `HingeController` swings them locally with creak/slam and makes loose shutters knock in the wind; `HomeownerController` swings the front door per entrance style. `Modules/Houses.of(door)` finds a door's house (the knock door now sits inside a door model).
- **Doorstep, voice and feel (2026-10-24):**
  - Knocking steps you back off the door and tilts the camera up at whoever answers (`DoorController` DOORSTEP).
  - Homeowners talk in a HUD-style panel, letter by letter, with a whispered voice (`DialogController`, `Config/Dialogue`: 6 eerie personalities). The Costume Line answer waits for the line to be read.
  - No names by doors. Sprint on Shift with an FOV kick (`MovementController`). No cursor in first person; the crosshair dot stays.
  - The music waits for saved settings before it starts.
  - Kenney CC0 sounds are packed into three uploaded sprites (`art/scripts/sound_sprites.py`, `Config/SoundSprites`). They give footsteps per surface (`FootstepController`), night ambience (`AmbienceController`) and UI sounds.
  - Every screen restyled to the HUD (`UI/Components/Chip` and the rest).
- **Open houses and entrance halls (2026-10-24):**
  - About one house a street stands **Open** (`HouseTypes`): its door swings open, its hall light comes on and flickers, and a figure stands far inside. The figure is gone when you come close and maybe back once you walk away (`HouseVisualController`). These are the future heist entrances.
  - **The halls were rebuilt bigger (2026-10-24, the user found them too small)**, on a kit in `interiors.py`: panelled wainscot with a chair rail, a cornice, doorways into darkness with casings, flights with a closed string, turned balusters and newels, a cupboard under the stairs, balustrades, and a ceiling rose with a chain.
    - **Victorian:** a vestibule, then a two-storey hall with a steep stair up to a gallery and a column.
    - **Farmhouse:** a hall the depth of the house; its stair climbs into a black stairwell through the ceiling.
    - **Mansard:** an imperial staircase in a two-storey hall, a central flight to a half landing and two flights back to a gallery over the vestibule.
    - The data files carry each hall (`Hall`: lamp, figure, props, `hang` piece, `drop`, `range`, candle `flames`). `BlenderLot.dressHall` hangs the new **Chandelier** (furniture.py) or the bare bulb and places the props. `HouseService` lights the flames along with the light.
- **Collisions, figures, dialogue (2026-10-24, the user found a porch collision wrong, dialogue too fast and stuck on screen):**
  - **Collision comes from the house data at runtime now** (`BlenderLot.collide`); the boxes baked into a template are replaced. Fixing a collider is code only: edit `colliders()` in the house script, rebuild the data (no export or import).
    - The Victorian's list moved from `tools/setup_victorian.luau` into `victorian.colliders()` / `VictorianRooms.luau`.
  - `art/scripts/colcheck.py <style>` compares the colliders with the model over a grid. It writes a top-down map (`art/renders/colcheck_<style>.png`) of floors you'd float over or sink into, invisible walls, and things you walk through.
  - **Fixed collisions:**
    - The Mansard's sloped cheek walls by the steps were full-height boxes that lifted you onto air; they're now four steps.
    - The Victorian's trim band (a sill at the door) is now a ledge you stand on.
    - The rotted porch holes are shallow pits.
    - The porch rocking chairs, the urn, the washtub, the back stoop handrail and the step stringers all collide.
    - Foundations and plinths stick out past the walls and now collide.
    - Every low window's sill, casing and shutters collide (`housekit.sill_colliders`).
    - The porch fascias collide.
    - The cellar doors are a stepped slope.
  - **Figures:** `art/scripts/figures.py` adds three smooth Blender figures to the furniture: FigureWidow (a veiled woman in mourning), FigureTall (a gaunt man with a skull of a head and arms to his knees) and FigureGirl (a nightgown, her hair over her face). They're used in the open halls and behind windows.
    - Each hall has five figure spots, far to near (`Hall.figures`, markers `HallFigure`, `HallFigure2`…).
    - The figure turns to watch you. While you watch the door from within 36 studs, the hall blinks dark every 3.5–7 s and it's a spot closer. It vanishes in a blackout when you come within 13 studs, and may return at the far end once you're 40 away.
  - **Doorstep sequence:** the server gives each challenge an `intro` (homeowner out + hello; `Homeowners.OUT_AFTER`, `HELLO_TIME` 4.2), and the mini-game's clock starts after it. The client holds you and starts the game after the intro.
    - Lines type at 20 letters a second, with real pauses and trailing "...", and stay for 1.8 s + 0.22 s a word.
    - A line stays pinned by the speaker's face wherever you go: smaller the farther off, hidden while they're off screen. It fades when they go inside or you're 32 studs off; it used to freeze where the face was last seen.
    - Homeowners linger 3.8 s after the game (`LEAVE_DELAY`), so their reaction gets read.
    - The Costume Line question types at 20 letters a second (max 4.5 s).
  - `/housetype Open` works.
- **Texture flicker hunt (2026-10-24, the user saw textures glitching):** `art/scripts/zfight.py` finds faces lying in one plane, facing the same way and overlapping (z-fighting).
  - Run it on an exported FBX, or on a build with `--zfight` (`victorian.py`, `farmhouse.py`, `mansard.py`; `furniture.py -- --zfight --self`). `--detail` lists each patch with its bounds and `--pair A,B` dumps triangles.
  - Faces buried inside a solid are left out. Faces against a wall or under a floor still show up in the report (backs of trims, wall bottoms and tops); read those as hidden.
  - **Fixed:**
    - `victorian.slab()` built every roof board, rake and bargeboard inside out (a mirrored basis), so the underside showed and fought the gable walls. All three houses were affected.
    - Room floors sat at the height of the Victorian trim band and the Farmhouse stone, and the porch decks at the foundation stones. The band, stone and Mansard frieze are now rings or have a recess.
    - Walls doubled up at every corner; they now stop `EPS` short.
    - Every Mansard window had a crown and a hood 0.005 apart, and its hood and dormer outlines crossed themselves.
    - The window glass, sash stiles, rails and muntins shared a depth. Sills dipped into the openings.
    - Smaller ones: the porch lattice slats, the attic vents, the Victorian's tower plinth (two squares made a star), the back stoop, friezes and the belt flush with the corner boards.
    - Furniture and yard: the trunk lid, the pram rim, portrait layers, the desk papers, the crib slats and the mailbox front.
    - The Mansard frieze had been a solid slab that filled the top of every upper room.
  - **Gotcha:** Python's `write_text` on Windows writes CRLF. The generators pass `newline="\n"` now, and a patch script must too.
- **Homeowners rebuilt in Blender (2026-10-24, in progress; the user found the AI ones awful and too metallic):** the approved style is the player kids' style gone wrong: chunky, soft, big heads, simple faces, matte materials, one horror idea each. The user rejected realistic doll, puppet and sack concepts.
  - `art/scripts/characters.py` builds all 17 owners in the rig's six parts, with their joint positions: `--lineup 0|1|2`, `--close Name,...`, `--sheet Names file`, `--export`.
  - `--export` writes `art/export/characters/Homeowners.fbx` (meshes `Char_Owner_<Name>_<Part>`, a baked atlas each) and generates `Config/CharacterModels.luau`. That file is an empty placeholder until the first export.
  - `tools/setup_characters.luau` files the imported meshes under `Assets.Characters`.
  - `CharacterRig` builds Blender owners from those meshes at their pivots, with no morph. `CharacterRig.ready` decides who `HomeownerService` can pick.
  - **A scarier pass (2026-10-25, the user said some weren't scary):**
    - Grinner's teeth were placed at double height; he now has fangs all round and a lolling tongue.
    - PumpkinSuit is carved with real boolean cuts (angry eyes, a fanged grin), not deleted faces.
    - TankTop and BagMan got bloodshot eyes; Cardigan got pinprick pupils.
    - SweaterVest's face is skin grown over his eyes and mouth.
    - Porcelain got black tears and something glinting inside the hole.
    - Bathrobe melts further and drips off his chin.
    - Butler's neck is broken: his head lies on his shoulder (`skin(roll=...)` keeps the face paint on it).
    - RavenMan now wears a crow-skull mask with red points in the sockets.
  - Every Blender owner's head carries a `Face` attachment (from `face` in the data). `HomeownerController.face` (dialogue, the doorstep camera) and the jumpscare aim at it, because long hair and veils put the head part's middle far from the face.
  - **In the game (2026-10-25):** `Homeowners.fbx` was imported: 102 parts, each with its own baked colour, normal and roughness maps (306 textures), with sizes matching the data. The setup script filed them under `Assets.Characters`.
    - All 17 build through `CharacterRig` with their joints and faces.
    - Verified at night doors in play: Grinner, Widow, Gown, PumpkinSuit and Butler.
    - Gotcha when posing a rig by hand: `PivotTo` moves the HumanoidRootPart (PrimaryPart) to the target, not the feet. The game uses the `rootOffset` from `HomeownerController.build`.
  - **The old AI homeowners are deleted (2026-10-25, the user asked):**
    - Removed from `Config/Characters` (TankTop, Curlers, SweaterVest, Porcelain, SackMask, PumpkinSuit) and `Config/Meshes` (Cardigan, Nightgown, Lanky, Bathrobe, Grinner).
    - Removed the fallback to them in `CharacterRig` and `MeshLibrary`, and `HomeownerController`'s one-piece-statue path.
    - Removed the earlier rejected `art/scripts/homeowners.py` and its renders.
    - A homeowner whose meshes aren't in the place is now simply never rolled (`CharacterRig.ready`).
  - **Loaded before play (the user saw them loading in as a door opened):** the loading cover now preloads, in order, `Assets.Characters`, `MeshTemplates`, then `Assets.Furniture` (45 s cap).
    - `PreloadAsync` fetches the meshes but not SurfaceAppearance maps; those load the first time they're seen. So under the cover each Blender homeowner is shown once, 8 studs in front of the camera.
    - Then the cover waits for `ContentProvider.RequestQueueSize` to drain (15 s cap) before it lifts.
    - **Still loading in (the user, 2026-10-25):** `PreloadAsync` skips SurfaceAppearance maps. It also fails on bare id strings, but the same id on an unparented Decal downloads.
      - The setup scripts now write each part's map ids as a `Maps` attribute (`setup_characters` and `setup_furniture`; already applied in the place). The cover preloads them through Decals: 596 downloads, none failed.
      - Homeowner meshes are `RenderFidelity.Precise` (no LOD pop).
  - **Every homeowner shows up:** every street deals from the whole cast (`Homeowners.CAST`) like a shuffled deck (`HomeownerService.roll`), so a street shows 16 different ones before any repeats. Before, each street had a pool of 4–5 and picked at random.
  - **Walking away calls the visit off:** while they come out and say hello you can move (movement locks only when the game itself starts).
    - Past `Economy.DOOR_LEAVE` (16 studs) from the door, the client drops the visit: no game, the hello is cancelled, the line is hushed, the look released. It sends `MinigameCancel`.
    - A server watcher does the same and sends `MinigameCancelled` if the client didn't.
    - No candy and no cooldown; the homeowner goes back in.
    - Verified in play: walk off mid-hello → no game frames, no dialogue, and the same door answers again at once. Staying → the game starts after the hello.
  - **The doorstep, reworked (2026-10-25). The user said they float and clip through things, the sounds needed work, and the player should step back and be held so they see everything. Later: "they appear before the door is open", "they sometimes don't face the player".**
    - **You step back and are held:**
      - When the knock is answered, `DoorController` walks you straight out from the door to where all of them is in view. `DOORSTEP` is now 6.5–10.5 studs, by their height, because they stop further out.
      - The camera stays on their face.
      - Movement is held from the answer, not only once the game starts. Holding a direction for 0.35 s walks away (a hint shows after 1.5 s), which calls the visit off as above.
    - **They walk, and it sounds like it:**
      - The stride follows the ground covered: legs and arms swing and the body bobs.
      - Every footfall is a heavy board (`OwnerStep`, `StepWood`, now and then `BoardCreak`).
      - The latch, then each style's creak; cloth and breath as they settle; `DoorShut` (`DoorSlam` for Rush) behind them.
    - **Nothing passes through the house or the door.** `HomeownerController.measure` works out each body against its doorway:
      - It samples a real door's swing (20 steps).
      - It takes the hall's depth from its figures' floor spots (the house collision is one solid box, so raycasts can't measure the hall).
      - It measures the body as rounded part boxes, the head nodding and turning and the arms and legs swinging (`reachOf`).
    - **Before the door has moved (the user's "appear before the door is open"):**
      - They wait deep in the hall, beyond the door's sweep: 5–9 studs.
      - They aren't in the world until the door moves.
      - Their walk is timed so they never get ahead of the door (`planGate`, `aheadOfDoor`). Before, they stood 0.6–2.8 studs in, and the inward-swinging 4.1-stud door went through them.
    - **Short halls:** the Mansard's vestibule is only 4.2 studs before its stairs, too short to wait clear of the door. There they stay out of the world while the door swings past, fade in out of the dark (`FADE`), and fade back out before it closes again.
    - **Too tall for the door:** they fold down gradually while still in the hall, hold the fold until clear of the wall, then straighten.
      - The fold turns about the root joint.
      - A nodding head counts: nodding lifts the back of the head.
    - **Sideways:** only someone whom turning makes narrower turns sideways through a door, and never while folded (folded, the turn swung the head into the wall).
    - **They face you (the user's "sometimes don't face the player"):**
      - They stop 2–4 studs out on the porch, with room to turn, and shuffle round toward you (up to 0.7 rad, small audible steps). The head does the rest.
      - Before, wide homeowners stayed turned sideways, and the head stopped following you right where they stood.
    - **Leaving:** they turn back to the door and back into the hall at walking pace (`LEAVE_PACE`), then the door shuts.
    - **Timing:** `Homeowners.OUT_AFTER` is 0.2–0.4 s longer per style. If a long hall still makes them late, the hello waits for them (`HomeownerController.arrivesIn`).
    - **Verified in play** with a harness that checks every frame: the Blender silhouettes against the wall over the frame, and rounded part shapes against the frame's sides and the swinging door.
      - Clean at Farmhouse, Victorian and Mansard doors with Lanky, MaskedLady, Widow, Gown, Butler, Grinner, RavenMan, Curlers, Cardigan and PumpkinSuit, across all five styles. Body and head end up facing an off-centre camera.
      - Painted Maple doors: nothing shows before the darkness covers the doorway.
      - A real knock: SackMask came out facing you, and you were stepped back to 8.4 studs.
    - **Not checked:** the halls' hanging lamps and props. Their paths run down the middle of the hall, clear of the props.
    - **Test gotcha:** CC_07 and CC_13 are Open houses. Their doors already stand open, so a forced visit there is measured in the wrong frame. Nobody answers there in the game.
- **Phase 2.5 finished off (2026-10-25): lobby and private runs, party buses, dawn, death.**
  - **Server modes** (`Modules/Mode`):
    - A reserved server with no owner is a run. Any other live server is the lobby (a player's private server too).
    - Studio plays `Game.STUDIO_MODE` (`"run"`; set `"lobby"` to test the lobby).
    - `init.server` loads only that mode's services: `Loader.run(..., unused)` skips the rest without warnings.
    - Clients read the `Mode` attribute on ReplicatedStorage. The HUD hides the bag and clock in the lobby.
  - **The lobby** (`World/Lobby`, built by `WorldService` in lobby mode):
    - A bus turnaround: a ring road round a paved island, 8 Blender houses all round (shut, lit, yards dressed), dead trees, lamps.
    - No Night there (`WorldEventsService` doesn't start one).
  - **Party buses** (`Services/PartyService`, `PartyController`):
    - Board through the door's prompt and you're sat in the bus. The first aboard hosts; up to 4.
    - Host: E/ButtonX starts a 5 s countdown, G/ButtonY toggles friends-only. Space gets you off. Touch screens get buttons.
    - A HUD tile shows the party. A sign over each door shows the host, the count and the lock.
    - At zero: `ReserveServer` + `TeleportAsync` with the party in the teleport data. Retries, and failures are reported. In Studio it just says it can't teleport.
    - Verified in Studio lobby mode: board, friends-only, countdown, the Studio notice, get off. The real teleport can only be tested live.
  - *(Superseded the same day: Nights were deleted, see "Batch 1" below.)* **A run goes Night after Night** (`NightRunService`; `WorldEventsService.setDawn`). The user said going back to the lobby every Night made no sense, so the design was reworked:
    - Dawn banks the buckets (the box cap applies) and shows a card: "DAWN · NIGHT N SURVIVED", candy collected, banked, doors knocked.
    - After `Runs.DAWN_BREAK` (15 s) the next Night starts in the same run: house types, cooldowns, open houses and homeowners reroll.
    - Each Night survived pays +10% candy (`Events.NIGHT_BONUS`, up to +50%), multiplied on top of the event cap.
    - Leaving is the player's choice: **LOBBY** in the TAB menu → "BACK TO THE LOBBY?" [LEAVE]/[STAY] → `RunLeave` teleports just them. The bucket stays with them.
    - Verified in Studio: `/dawn` → card → Night 2 by itself with a reroll; the confirm window. The teleports are live-only.
  - **Lives and death** (`LivesService`, `RunController`): *(the lives were replaced by health on 2026-10-26: `HealthService`, see "Feedback round 2")*
    - Lives refill every 20 min, counting time away. `LivesService.faint(player, wakeAt)`:
      - Costs a life and the carried bucket. Out of lives: −50% banked candy and the lives refill.
      - The character is held and the screen goes black with a "YOU FAINTED" card. They come to at `wakeAt` or the spawn after 3 s.
    - The heist's homeowner will call this. `/faint` tests it (verified: 3→2 lives, bucket 5,500→0, banked untouched, refill timer started).
  - **Art: the party bus and a street lamp in Blender** (`art/scripts/lobby.py` → `art/export/lobby/Lobby.fbx`; `tools/setup_lobby.luau` → `Assets.Lobby.Bus`/`Lamp`).
    - The user found the first box-built bus "like shit". The rebuild:
      - A conventional school bus: rounded roof and caps, a sloping hood with a chrome-ringed grille and twin headlights, flared black fenders, a white roof with hatches.
      - Rubber-sealed rounded windows in a riveted body with rub rails and panel seams. One pane is broken, one boarded.
      - The crossview mirrors, the stop arm, eight-way lights, "SCHOOL BUS" boards, "HOLLOW PINES SCHOOL DIST.".
      - Inside: vinyl benches with grab rails, the driver's seat and dash with faintly lit gauges, ceiling ribs, three bare lights, a forgotten backpack.
    - "Make sure everything is in the same style, look at the houses": recoloured to the houses' palette (faded mustard paint, rust patches, grime, a mossy roof). It's checked in their daylight preview light next to the Mansard.
    - "Work on the wheels":
      - Tyres with a rounded sidewall and staggered tread.
      - Off-white steel disc wheels with hand holes cut through the dish, ten lug nuts and a hub cap. Brake drums behind.
      - Deep-dish twins at the back with mud flaps, and black arch liners.
    - The lamp: a cast-iron post with a four-paned lantern glowing like the houses' porch lights.
      - `Props.lamp` uses it once imported, so the streets get it too.
    - Markers: `Mark_Origin`, `Mark_Door` (the prompt), `Mark_Seat1..4` (the party's seats). The setup script adds a collider, headlight SpotLights, the interior bulbs and the lantern's light.
    - The loading cover preloads `Assets.Lobby`.
    - Seated in a party seat, the tall backs blocked the view, so they were lowered: a seated kid sees down the aisle and out the windshield. The party sits two rows back. The interior is smooth painted steel (`victorian.textured(bump=)`, default 1 for the houses). The bulbs cast no shadows, so your own body doesn't black out the seat ahead.
    - "This looks glitchy" (the doorway). Fixed:
      - The rub rails, rivets and a marker light no longer cross the door.
      - A rubber seal runs round the opening, and the glass leaves fold flat against the frame.
      - Three real steps with worn white edges, dark stairwell walls, and a barrier by the first seat.
    - Imported three times (the last with the doorway fix) and set up. Checked in the lobby in Studio.
  - **UI the user couldn't read or use:**
    - Hosting is now big:
      - A lobby band: "WALK UP TO A BUS DOOR AND PRESS [E] TO HOST A RUN".
      - Large signs over each door ("PARTY BUS · press E at the door to host a run" / "X'S PARTY 2/4 · press E to join"). They're raised above the roof, and the bus streams in whole so the sign finds its door.
      - On the bus, a big band: "PRESS [E] TO START THE RUN", or "WAITING FOR X TO START", or the countdown. The party is listed on the right.
    - **A cursor in every menu** ("now I don't know what I'm pointing at"). In first person the mouse still *reads* as locked while a Modal frees it, so `CameraController` now shows the cursor whenever a Modal button is on screen. That covers the radial menu, the shop and wardrobe panels, the dialogs and the leave confirm. Gameplay keeps just the crosshair dot.
  - **Still part-built (not in the houses' style), for the map work:**
    - The hub on Home Street: shop stall, title sign, its bus.
    - The Candy Box drop-offs, the street gates, the bus stop signs and benches, the simple pumpkins.
- **Batch 1 of the user's big list (2026-10-25): pace, freedom at the door, feedback.** The user then asked for small prompts instead of one big one.
  - **Nights deleted.** It's always night. The Witching Hour comes round on its own clock: `Events.WITCHING_EVERY` (10 min) calm, then `WITCHING_LENGTH` (3 min) at ×2.
    - When it ends, the town changes (house types reroll on `WitchingEnded`).
    - The clock chip reads `WITCHING HOUR IN m:ss` or `WITCHING HOUR ×2 m:ss`. `NightRunService`, Dawn, the night bonus and `/dawn` are gone; `/event calm` ends it.
    - The sky goes red slowly (12 s blend): red fog with haze and glare, red night light (`ZoneLightingController`).
    - **The moon turns red** (`MoonController`, new). The sky's own moon keeps its texture under a red disc that gets more solid over the first 50 s, swells 25%, with a red glow round it, then holds still until the hour ends and fades back over 8 s. No other animation (a heartbeat throb read as blinking to the user). The Blood Moon event keeps it red all event.
  - **Faster pace:**
    - Homeowners come out and go back in about 40% sooner (`HomeownerController` WALK/doorOpen/leave, `Homeowners.OUT_AFTER`, `HELLO_TIME` 2.4, `LEAVE_DELAY` 2.0).
    - Lines type twice as fast and leave sooner.
    - **Skippable:** click, Enter, Space or Ⓐ shows the rest of a line; pressing again puts it away. Putting their hello away starts the mini-game at once (`MinigameSkip`; the server restarts the clock). Verified: game at 3.3 s instead of 4.8 s.
    - Once a line is all out, moving the mouse puts it away.
  - **You can move during a visit, but not far:**
    - `Economy.DOOR_LEASH` (11 studs from the door) holds you on its edge. Keep pushing out for 0.6 s and you leave ("keep walking to leave"). `DOOR_LEAVE` 16 still calls it off.
    - The walk back to the doorstep still happens; walking yourself overrides it.
    - Your view lets go of the homeowner as soon as you move the mouse or the right stick.
  - **A full bucket can't knock.** The doors say "Bucket full · Empty it at your Candy Box", and the server refuses with a toast.
  - **Door cooldown ring** (the user's reference: a ring timer, time left in one colour, time gone in another). In the HUD palette: 48 rounded segments, bright for the time left and dim for the time gone, sweeping clockwise from the top. The segment at the edge fades over as it goes, so the sweep creeps rather than ticks. The seconds sit in a dark disc, see-through like the HUD's tiles. (A solid-ring version was tried and rejected; the user kept the segments.)
    - It used to come up with 2-3 segments already gone, because the door takes ~4 s to shut after the result. Now the server's cooldown counts from about when the door shuts (`Homeowners.LEAVE_DELAY + SHUT_AFTER`), and a ring that appears after your own visit starts full. Verified: 90 at appear, 87 three seconds later, 81 nine seconds later.
    - It's **3D, flat on the door's face**: a SurfaceGui on its own part in `Workspace.DoorRings`. Inside the door model the hinge swing carried it off.
    - It fades in only **after the homeowner has gone in and the door has shut** (`HomeownerController.atDoor`). Verified.
  - **Get it wrong and they slap you** (the user: "they slap, not hit"; `HomeownerController.strike`, `SLAP`). On a MISS (any game, a wrong or timed-out costume answer):
    - The hand is drawn back out to the side as the body turns away. Then it swings flat across at your face as they lunge and turn through (legs planted), with a whoosh.
    - When it lands, **your head snaps 30° the way the hand was going** and tips 9°. It holds a moment, then turns back over about 0.55 s (`DoorController.hit`; the camera keeps the turn, so only each frame's change is added).
    - Also: a slap (Kenney's soft impact sped up, until a real slap clip is in a sprite), a little shake, red at the screen's edges (not with Reduce Flashes), and a short shove back. Then they tell you off.
    - Verified by recording the shoulder, body and camera every frame.
  - **Dialogue is 3D** (the user: "things like this cooldown and dialogues should be 3d"; then: too high, didn't face the player, not lined up with the homeowner).
    - The panel sits beside the speaker's head at about mouth height (`MOUTH` under the eyes), on your left of it.
    - Its leader runs straight in from the panel's side to the head's edge as you see it: the head's box measured along your view's left, `ROUND` for round heads.
    - It's square to your screen (no tilt when you look up at a tall homeowner). It's drawn a little bigger far off, and is more solid than a HUD tile so porch lamps don't wash it out.
    - So nothing on the porch hides it, it's drawn at most `NEAR` (3.5) studs from your eye on the same line of sight, scaled to match. It looks just the same, beside their head.
    - `SurfaceGui.AlwaysOnTop` rendered nothing at all (the earlier "always on top" fix had made lines invisible); removed here and from the head pop-ups.
    - Your reply chips stay on the HUD (your own input). They're gone the instant you answer, or when the time runs out (the user asked). No right/wrong colouring any more: the grade and the slap say how it went. The question goes 0.4 s later. Verified both ways in Studio.
    - **The line is gone before they go back in** (the user asked). The line timing is shared (`Config/Dialogue.TIMING`, `lineTime`).
      - The server keeps the homeowner out until their reaction has typed, held and faded, plus `Homeowners.AFTER_LINE` (never less than `LEAVE_DELAY`). The door's cooldown counts from that.
      - If they start back in early (a visit called off), the line goes at once.
      - Verified: line gone at 3.20 s, turning back in at 3.58 s.
  - **Shift no longer "changes your height":**
    - The sprint FOV widening (+8°) read as rising up, so it's gone, and the head-bob no longer grows with speed.
    - Roblox's Shift Lock is off (`StarterPlayer.EnableMouseLockOption` false in the project, and `DevEnableMouseLock` false per player).
  - **Bus seats see more:** sat on a party bus seat your view is raised 1.4 studs (`PartyController`).
  - **Who's on the bus shows from outside** (the user asked): each party seat has a warm SpotLight in the roof over it, on while someone sits there (`Lobby.luau`, `SEAT_LIGHT`). It's server-side, so everyone sees it.
  - **Seated properly:**
    - Our characters had no sitting pose, so kids stood inside the bench. Now they sit: legs out in front, a slight lean back, hands in the lap (`CharacterAnimController`, `SIT`).
    - A Roblox seat holds the middle of the body at its top, which sank the hips 0.5 studs into the cushion. The seat's top now matches the cushion (`SEAT_ON_BENCH`). Each build is raised by what it needs (`sitLift`): thighs on the cushion, nothing of the body below it. The ghost sheet sits on its hem.
    - The benches were 3.05 apart, leaving 1.6 studs of leg room against the 2.2–2.4 the kids need. `art/scripts/lobby.py` now has 6 rows 4.2 apart; the party seats stay on rows 2 and 3.
    - The user imported the re-spaced bus; `tools/setup_lobby.luau` was run through the MCP (party seats now 4.2 apart).
      - Verified with the biggest costume (ghost sheet): feet 2.39 ahead of the seat marker with 2.66 of room, the back touching the backrest's foot without going in, the sheet on the cushion.
    - The carried bucket is put away while seated: worn on the back, it went through the seat back (`CharacterAnimController`, every client).
  - Checks: stylua, selene, 55 Lune tests and the rojo build pass. Verified in Studio: knock, step-back with movement on, 3D hello, skip, MISS hit (flash and knockback), ring after the door shut, red sky and moon.
  - **Not verified in Studio:** the leash edge, the full-bucket doors, the raised bus seat, the last moon nudge (disc lifted 2.5%, deeper red), and the strike's arm swing on screen. Studio hung starting a play session.

- **The rocking chair is off the Victorian's porch** (2026-10-25, the user asked). It's gone from `art/scripts/victorian.py` (the mesh and its collider), `HouseData/VictorianRooms.luau` (the collider in game) and the part-built fallback (`HouseStyles/Victorian.luau`).
  - Re-exported to `art/export/victorian/Victorian.fbx`. **Needs the user to re-import** (File → Import 3D) and run `tools/setup_victorian.luau`. Until then the old mesh still shows the chair, but you can walk through where it was.

- **More homeowner moments (2026-10-25, the user: "more animations/interactions like homeowners peeking through the door").** All server-driven, so everyone sees them.
  - **Peeks at passers-by** (`HomeownerService`, `Glance`/`GlanceSlam` on the house; `HomeownerController` glance figures).
    - Rare (the user: "peeking should be rarer"): every 28–55 s, one house someone's walking past (9–38 studs from its door) cracks its door to 40% for 2.5–4 s. Its homeowner stands off to the side of the gap, leans into it, and watches the nearest kid (`OwnerVisitor`).
    - Come within 9 studs and the door slams. A house rests 3 minutes between peeks; only one peeks at a time.
    - Knocking turns a peek into a normal visit.
    - Tall homeowners that can't peek round a door just crack it on the dark.
  - **The candy hand-off:** on any good result the homeowner reaches out (`HomeownerGive`). A piece of candy (one of the receiver's own bucket pieces) leaves the hand and arcs into your bucket at the bottom of your view (or into another kid's), with a pop.
  - **Goodbyes** (reworked: "work on goodbyes"). The server picks one to fit how the visit went (`OwnerBye`, cleared at each knock). Going back in, they do it still facing you, then turn to the door (`HomeownerController.GOODBYES`, each a pose over time).
    - **Did well:** a slow wave with the hand up by the head and the head tilted; a deep bow held too long, eyes still on you; or two nods with a small raised hand.
    - **Didn't:** a finger jabbed at you twice, leaning in; a shoo (the back of the hand flicked at you, head turned away); or a long stare, the head tipping over. These end with the **door slammed**.
    - Verified the wave (arm out and swinging at the head, ~1.4 s) and the bow (0.77 rad bend, held ~1.2 s) by recording the joints.
  - Verified in Studio:
    - The plague-doctor homeowner peeking through a 40° crack (screenshot).
    - The candy left the hand at 4.48 s and landed at 5.28 s.
    - The point raised the arm to 1.55 rad before they turned.

- **Everyone sees the same thing (2026-10-25, the user: "everything should be visible to everyone, synced").**
  - Already shared before this: the homeowner coming out and going in, the doors swinging, characters' animation, footsteps, costumes and buckets, the Witching Hour sky and moon, the party buses.
  - **What homeowners say** is now decided by the server (`DoorService.say`/`line`, the house's `Config/Dialogue` personality). It's sent to everyone (`HomeownerSay`: house, text, server time to show it), so everyone near the door sees the same hello and the same reaction.
    - The Costume Line question goes to everyone except the visitor, who gets it with the answers.
    - Walking away from your own visit drops what's still to come, for you.
  - **The slap** is the server's too (`HomeownerStrike`: house, who). Everyone near sees the homeowner slap that kid and hears it land on them; only the slapped player's head turns. What they say after waits for `Homeowners.SLAP_LANDS`.
  - **The homeowner faces whoever knocked** (`OwnerVisitor` on the house), for everyone. Before, each player saw them turn to their own camera.
  - **Heads look up and down where their players do.** Each client sends its look (`LookPitch`, about 8 times a second when it moves). The server puts it on the character, and `CharacterAnimController` tilts that head for everyone else.
  - **Second pass** (the user: "cooldown should sync too, think of all the things that should sync"):
    - **Door cooldowns are per house, shared.** Once a homeowner has answered (or a bowl's been raided), nobody gets anything there until it's over.
      - It's on the house model (`ReadyAt`, server time), so everyone sees the same ring and the prompt is off for everyone.
      - A second visitor's result only stretches it. `CooldownsReset` is gone; `DoorService.resetCooldowns` clears the attributes.
    - **Knocks are heard** by everyone near (`DoorKnocked`).
    - **Scares are seen:** when someone gets the Nerve Hold jumpscare or is caught at a bowl, everyone else sees the homeowner lunge out at them and hears the scream from the door (`ScareSeen`, `HomeownerController.lunge`). The victim still gets the camera jumpscare.
    - **Results over heads:** others see a 3D pop-up rise and fade over a player's head, like "PERFECT +24", "CAUGHT -50" or "+300 STASHED" (`PlayerPop`, new `PeersController`). Your own stay on your HUD.
    - **Fainting is seen:** the character drops flat on its back where it stood (`Fainted` on the character, `CharacterAnimController`).
    - **The open-house hall figure is the server's** (new `HallFigureService`, `HallSpot`/`HallGone` on the house).
      - It comes a spot closer while anyone watches the door, and is gone when anyone comes close.
      - Every client blinks the light and moves it together; it turns to whoever's nearest.
  - **Still personal (on purpose):** the mini-game screen and grade on your HUD, the jumpscare camera, menus and the shop, your own lives and bucket numbers, which gates you've unlocked, background ambience and music.
  - The flashlight was deleted (the user: there'll be no flashlight in the game).
  - Verified with one player in Studio: knock, line, slap, pop-up and `ReadyAt` (94 s, 90 plus the door shutting) all sent; the hall figure stepped 1 → 2 → 3 while watched and went in the doorway on both server and client; `/faint` laid the rig flat. Earlier: hello and Costume Line question sent to everyone, slap and reaction on a MISS, `LookPitch` 0.6 when looking up 35°, `OwnerVisitor` set. Two clients at once can't be run through the MCP.

- **The car (2026-10-26).** The user asked for a random car that drives often; if it hits you, you're ragdolled and lose all your carried candy. Then they said "every 5min or sum".
  - **The model** (`art/scripts/car.py`, Blender, the houses' pipeline; renders `art/renders/car_{front,side,back}.png`):
    - A 1950s pontoon sedan left out for decades: faded black-cherry paint with rust through it, a toothy chrome grille, round headlights, wrap-around bumpers with bullet guards, a hood ornament, whitewall tyres on body-coloured steel wheels with chrome caps, dark glass, and an empty bench seat with nobody at the wheel.
    - Every wheel is its own meshes, so the game can roll it.
    - It exports to `art/export/car/Car.fbx` (30 meshes). `tools/setup_car.luau` files it under `ReplicatedStorage.Assets.Vehicles.Car`. It makes a model per wheel on its axle (with a `Radius` attribute) and adds headlight spots, a glow and red tail lights.
    - Exporter fix (`export_victorian.bake`): a metal material bakes no diffuse colour, so chrome came out pure black. It now bakes metals as if painted. **The bus's chrome is black in the game for the same reason**: it needs a re-export of the lobby to pick this up.
  - **How it drives** (`Config/Traffic`, new `TrafficService` + `TrafficController`):
    - A street with someone on it gets a car every 4–6 minutes; the first comes after 1–2.5 minutes.
    - The car comes out of the mist 26 studs in from one end, headlights first. It drives the street in the right-hand lane at 40–48 studs/s (it swerved round the middle Candy Box until that was removed in the second pass), and fades back into the mist at the other end.
    - Its headlights waver, the engine rumbles (looped from the car itself), the wheels roll, and it honks at anyone in front of it, at most twice a trip.
    - The path is shared (`Traffic.pose`, on server time), so the server's hit check and every client's car are in the same place (`CarTrip`).
  - **The hit:** the server checks the car's box against everyone (0.1 s back, to match how far behind it sees players), once the car is mostly out of the mist. If you're hit:
    - You're thrown the way the car was going (up and off to your side) and ragdolled for 3.2 s by the new `RagdollService`: ball sockets with limits at the neck, shoulders and hips, and limbs that collide.
    - Your own client does the throw and the fall (new `RagdollController`). The view leaves your eyes and follows you from behind and above, and your hand's bucket is hidden. When the joints lock back, you're stood up where you landed and back in first person.
    - **Everything in your bucket is gone** (banked candy is safe). Everyone hears the thud and sees your candy fly out of your bucket and bounce across the road (`CarHit`), with "RUN OVER -N 🍬" over your head (`PlayerPop`). You get a red flash and "Run over! -N candy from your bucket".
  - Sounds (ProSoundEffects, load-tested in Studio): engine `Hot Rod Humming Idle 1`, horn `Ferrari 308 … Dual Air Horns 2`, hit `Metal Whomps … 8`.
  - `/car [down|up]` sends one down the street you're on, now.
  - Traffic stays off until the car is set up (Output warns once).
  - Verified in Studio with a stand-in box for the car (only for that play session):
    - Hit 3.2–3.8 s after `/car down` from 124 studs away; thrown ~25 studs.
    - The bucket went 533 → 0 with banked candy untouched, and the joints came back.
    - Screenshots: the chase view, the limp body on the sidewalk, candy flying, the toast and flash, the hand bucket hidden.
    - After getting up: the camera is Custom on the humanoid, the body upright, the state Running. No errors from our scripts.
  - **To do (user):** File → Import 3D `art/export/car/Car.fbx` into Workspace. Then run `tools/setup_car.luau` (I can run it through the MCP), and save and publish.

- **Second pass (2026-10-26).** The user: "the ragdoll shouldn't be from 3rd person, work on the car more especially on wheels, add the slap sound I gave u, delete candy box from the middle of the street, add grain effect on camera like ps1 graphics, re-export the bus".
  - **Ragdoll in first person** (`RagdollController`):
    - The view stays in your eyes and goes with your head (thrown, tumbling, landing however it lands), eased a touch against physics jitter.
    - Your flopping body shows; your own head stays hidden.
    - Verified in Studio: from the head as you're thrown, then back to the normal first-person camera, upright.
  - **The car, more detail, mostly the wheels** (`art/scripts/car.py`, renders `art/renders/car_{wheel,front,side}.png`, re-exported `Car.fbx`):
    - The tyres are 1.1 wide, with stepped tread blocks either side of a centre groove (two rings at each block edge, so the steps are sheer and shade cleanly).
    - The whitewalls are aged cream. The steel wheels are body-coloured, dished, with six punched slots.
    - Each wheel has a chrome trim ring (an open lathe, so it doesn't cap over the middle), a domed chrome cap, a boss with a two-eared spinner, and a red badge. The slots and spinner show the wheel turning.
    - New on the body: a chrome mirror on the driver's door, wipers, a whip aerial on the front fender and an exhaust pipe.
    - `setup_car.luau`: the wheel looks are updated (metal rim and chrome, yellowed wall).
  - **The middle Candy Box is gone** from every street (`Street.luau`: drop-offs at the entrance and end only; 5 in the world now). The car no longer swerves (`Traffic.pose` holds its lane).
  - **PS1 grain** (`CameraController`, `Config/Images.Grain` = "noise2", a loopable noise from the Creator Store; the old one showed a tile grid):
    - The noise is tiled at 384 px, sampled pixel-sharp, slightly darkened so it doesn't lift the blacks, at 0.8 transparency, and jumps ~20 times a second.
    - Settings → PSX effects still turns it off. Tuned live in Studio by screenshot.
  - **The slap sound** the user gave (`slap_sound.mp3`) is trimmed and saved as mono `art/export/audio/TorT_Slap.ogg` (2.6 s).
    - The user uploaded it: `Sounds.Slap` = 82925254970803 (found in their inventory, load-tested), at volume 0.4 (at 1 it was too loud, the user said).
    - The old Kenney clip and the thud layered under it are gone.
  - **The bus re-exported** (`art/export/lobby/Lobby.fbx`) with the chrome bake fix, so its chrome has colour now.
  - **Imports set up (2026-10-26):** the user imported `Victorian.fbx`, `Car.fbx` and `Lobby.fbx`, and I ran `setup_victorian`, `setup_car` and `setup_lobby` through the MCP.
    - The porch chair is gone from the street's Victorians (screenshot).
    - Car bug fixed: the importer leaves each mesh a rotated pivot offset (Blender Z-up). `CarPaint` is the car's PrimaryPart, so the car's pivot came out turned -90° about X, and it drove standing on its end, headlights up into the sky.
      - `setup_car` now resets every part's `PivotOffset` to the car's origin, as `setup_lobby` does.
      - The template in the place was fixed the same way.
    - Fresh imports show "Asset content representation is being generated" in Output for a few minutes, while Roblox processes the meshes and textures. They draw nothing until then.
    - Verified in Studio after the fix: a parked copy sits on its wheels with the tail lights at the back, and a car on `/car down` comes at you headlights first.
    - The pale sheet in the sky was a stray `candy` model in Workspace: 253 × 100 × 109 studs, 60 studs up, seen only when the headlights lit it. Deleted at the user's request.

- **Candy is the user's candy bar (2026-10-26).** The user imported a wrapped candy bar (inventory model "candy-bar", 96785013814575) and asked for it as the candy.
  - `tools/setup_candy.luau` files it as `ReplicatedStorage.Assets.Candy.Bar`, scaled to 1 stud long (it came in 489 studs long). I ran it through the MCP.
  - New `Modules/CandyPiece` makes every piece: a bar 1.5× the size of the ball it replaces, laid in a jumbled pile (any way round, tipped a little). It falls back to the old coloured ball until the bar is in the place. `Parts.candy` is the server props' wrapper.
  - Used for the bucket fill (`Buckets`), the Candy Box topping (`Props`), the shop's jars (`Hub`), the take-one bowls (`HouseService`), the candy a homeowner hands over (`HomeownerController`) and the car hit's burst (`TrafficController`).
  - Verified in Studio: the Candy Box shows a pile of wrapped bars, and the bucket shows bars sticking out of the top as it fills.
  - The wrapper's logo looks like a real brand's (Mars), which could get the asset moderated; told the user.
  - The stray `candy` model (a first try, hundreds of studs across) was the sheet in the sky; deleted.

- **The Knifer (2026-10-26, placeholder block for now).** The user: a serial killer who roams the streets and appears from nowhere (out of a building, from behind one). The only warning is a sound when he appears, his loud footsteps and chase music. Catching you kills you with no second chance. He's not hard to escape: you hide in bushes and gardens. Lose him and he goes to your last known position, looks around it, then goes back somewhere he can disappear. He hears you walk and run.
  - Settings live in `Config/Knifer`; the numbers are my defaults:
    - A street with someone on it gets him every 3.3–6.3 min, the first after 1.5–3.3 min. He stays 50–80 s, and is gone 45 s after that whatever he's doing.
    - Speed is 9 roaming, 11 searching, 14 investigating and 20 chasing (you walk 16 and sprint ~26).
    - He sees 90 studs in a 150° cone, any direction within 10. Inside a `HideSpot`-tagged part he only sees you within 7.
    - He hears walking within 20 studs and running within 55. He gives up a chase after 2.5 s out of sight.
    - He catches within 4.2 studs, and searches 3 spots within 14 studs.
  - **Server** (`KniferService`, RUN_ONLY):
    - Spawns at an unseen exit 25–75 studs from a player: an Open house's doorway, or round a house's back corners. No one within 45 studs may see the spot.
    - States: appear (0.7 s) → roam (wanders the road and pavements; doesn't know where anyone is until he sees or hears them, so hiding works) → chase / investigate → search → leave (walks to the nearest unseen exit and vanishes).
    - Moves as a Humanoid on an invisible slim root floating 2 studs up, so it steps up kerbs, with PathfindingService paths, and straight at you when he can see you.
    - If he's wedged for 2.5 s he's nudged on and picks a new goal. That happened between two houses' collision boxes by the pavement.
    - Kill: `LivesService.down(player, push)`, others see "KNIFED". The user: "change the screen when he catches you to just ragdoll".
      - Same cost as fainting (a life and the bucket; `pay` is shared with `faint`), but no black screen and no card.
      - You're shoved away from him and drop as a ragdoll (`RagdollService`, from your own eyes) for `Runs.DOWN_TIME` 4 s.
      - Then a quick 0.25 s fade and you wake at the spawn, so he can't catch you again on the spot.
      - The cost shows as a toast ("The Knifer got you · ♥ 2 left · -N candy from your bucket"; `Downed` remote, `RunController`).
      - Verified in Studio: ragdoll on, no Fainted pose, no anchoring, no card; respawned 4.0 s later; the camera back on the new body; the toast shown.
      - A test took the profile's last life and so half its banked candy; I gave the 118 back with `/candy`.
    - The model is Persistent-streamed, tag "Knifer", attributes Street/State/Target.
  - **Client** (`KniferController`):
    - The sting (`Stinger`) for everyone on his street the moment he appears (`KniferCame` remote, so it works however far off he is).
    - His heavy footsteps: ProSoundEffects "Foot Stomp 3" lowered, 3D, a step every 2.8 studs walking and 4.2 running.
    - The chase music (`MusicController.setChase`, APM "Pista Omicida 2nd vers.", fades in and out in 0.4 s) while he's after you, or after anyone within 30 studs of you.
  - **He patrols with sense** (the user: "better pathing, so he walks with sense, not just randomly"):
    - He learns each street once in the background (`lotsOf`). Per house: the pavement in front, the foot of the porch steps, and the gaps down its sides (looking on into the back gardens).
      - A yard or gap only counts if he can walk to it from that pavement within `PATROL.reach` (75 studs, checked with PathfindingService). Gates and fences rule out the rest.
      - On Cardboard Court that leaves 14 front yards and 25 side gaps of 16 houses.
    - Roaming is a patrol (`planPatrol`): along one pavement, the way he's heading, to the next house. There he may go up the path to stare at the house (20%), down a side gap to look into the back gardens (25%), straight across the road (12%), or stop and look round.
    - At the end of a side he crosses over and comes back up the other. He sets off into the street, not off its end.
    - Standing, his gaze sweeps ±0.7 rad round what he's looking at (no more spinning). A step that's far off or takes over 15 s means he plans again from where he is.
    - Searching after losing you, he checks the hiding places nearest where he last saw you (the spot itself, then the side gaps, front yards and HideSpots within 30 studs), pausing at each, looking into them.
    - He comes out of the side gaps that lead to the street, and only out of open doorways whose yard does.
    - Pathfinding keeps 1 stud off walls and his collision body is slim (1.4), so yard gates fit him. The rough bounding-box "room" check is gone: it made whole fenced yards look solid.
    - `/knifer info` says what he knows of the street you're on.
    - Verified in Studio: from a side gap to the pavement in 5 s; across the road nearly straight; down the pavement house by house; a side-gap peek and a front-path stare; into a gap and gone when his time was up. An earlier run walked right past a test HideSpot on the pavement and saw me inside 7 studs, as designed.
  - **He's the SackMask homeowner** (the user: "pick some model we already have"): burlap sack head, one button eye with the other torn out, a stitched grin, overalls (`Knifer.CHARACTER`).
    - Built with `CharacterRig.build(..., "player")`, so `CharacterAnimController` walks and runs him on every client. Sight comes from his head; paths use his own height.
    - Taken out of the homeowners' cast (`Config/Homeowners`), so the killer is never the one at a door. That leaves 16 homeowners.
    - If his meshes aren't in the place he falls back to the old stand-in: a 2.2 × 6 × 1.6 dark block with a red eye slit.
    - Verified in Studio: spawned as Owner_SackMask (tags Knifer and TorTRig), screenshot mid-stride on the road, and a chase → catch → ragdoll in 1.7 s. The tests cost the test profile lives (they refill).
  - `/knifer` brings him to your street now; `/knifer away` sends him off.
  - Verified in Studio:
    - He came out of a back garden, walked round to the street, saw a still player 89 studs off and ran them down: chase → kill in 4.4 s, faint with the knifer card.
    - Hidden player (in a test HideSpot) and quiet: he wandered 530 studs in 62 s without finding them, left and vanished.
    - Chase music crossfaded in, and his footstep sounds played on the client.
  - Not built yet: real bushes to hide in (Blender, tagged `HideSpot`), his Blender model, a knife, and a stab sound. Test profile: my tests cost the Studio test profile 2 lives (they refill on the timer).

- **Sync pass for the new things (2026-10-26, the user: "make sure everything is synced, the ragdolls etc.").**
  - **Ragdolls replicate.** The victim's client owns the physics, the server makes the joints loose (ball sockets, limbs given to that player), and the server and every other client get the motion.
    - Checked from the server's side, which is what every other player gets. Car hit: thrown at 43 studs/s, tumbling, lying at ~100°, limbs 70–95° off their rest pose. Knifer kill: lying at 88°, no Fainted pose.
    - Other clients' `CharacterAnimController` leaves the joints to physics (`Ragdoll` attribute).
  - **The car is now the same for everyone:**
    - The server decides the honks (`CarHonk`: someone in front of it). Before, each client honked on its own.
    - Each trip has a `seed`, so the headlights' waver (seed + server-time step) and the engine's start match on every screen.
    - A hit carries a seed (`CarHit`), so the candy flies the same way on every screen.
    - Verified: the honk and the hit's seed arrived on the client.
  - **The Knifer's kill is heard by everyone near** (`KniferStruck`): a deep thud and ProSoundEffects "Body Fall Master 4" at the victim. Verified that the event reached the client.
  - Already shared: the Knifer himself (one server model, Persistent, his walk animated on every client), the sting for his street, his footsteps from his replicated movement, the car's path (server time), the bucket fills and candy bars, the homeowner giving candy.
  - Personal on purpose: your first-person ragdoll view, the chase music, the red flash, the toasts, the grain.

- **Animation pass: the Knifer and the homeowners (2026-10-26, the user: "work more on the knifer, more animations, the same with the homeowners").** Written, linted and tested (55 pass), **not yet seen in Studio**: the Rojo plugin needs reconnecting, and the knife needs importing.
  - **His knife** (`art/scripts/knife.py`, Blender): a butcher knife with a steel blade and a dark, bloody edge, a wooden handle (CC0 dark_wooden_planks), a steel bolster and 3 brass rivets. Render: `art/renders/knife.png`. Export: `art/export/knife/Knife.fbx`.
    - `tools/setup_knife.luau` files it as `Assets.Props.Knife`: a Grip part (PrimaryPart) with the pieces welded to it, unanchored, massless, no collision.
    - `KniferService.arm` welds a copy into his right fist, the blade out along the back of the arm (`Knifer.KNIFE.grip`). With no knife in the place he goes without one.
  - **The Knifer has his own animator** (`KniferController`, at the same choppy 14 poses a second). `CharacterAnimController` skips any rig with `OwnAnimator`.
    - Gait: a stiff stride, one leg limping, a hunch that deepens when he runs or searches, a bob on each step. The left arm hangs dead when he walks and pumps when he runs.
    - The knife arm follows his state: hanging at his side on patrol, held ready when he's investigating, raised over his head in a chase. On the kill: a two-stab overhand swing (`STAB` keyframes), then he stands over you looking down.
    - The head: down when he appears, then a snap up (`SNAP_UP`). In a chase it tracks the target's head. Otherwise a slow scan, with sudden snaps to one side, held.
    - Heavy breathing now and then.
    - Everything is from server time and his `Seed` attribute, so his head snaps and breaths match on every screen.
  - **Homeowners do things at the door** (`HomeownerController` ACTS). Every 4.5 s there's a 55% chance one starts, picked from the house's `OwnerSeed` and server time, so everyone sees the same act:
    - a look back over the shoulder into the dark house;
    - the head cocked over too far and held;
    - a scratch at the side of the head;
    - fingers drumming on the leg;
    - weight shifting from foot to foot;
    - leaning in for a closer look;
    - sniffing the air.
  - **They gesture as they talk:** `HomeownerController.talk`, called by `DoorController` with each line. The far hand beats with the words and the head nods.
  - **A slow clap at a PERFECT:** `HomeownerGive` now carries the grade. On a PERFECT, three claps with a clap sound (`Sounds.Clap`) come first, then they hand over the candy.
  - To check in Studio: the knife sits in his fist; the arm is raised in a chase; the stab; the head snap. The acts, the talk gestures and the clap.

- **Movement and camera rework (2026-10-26, the user: "new perfect satisfying player movement with crouching, sprinting… very polished… also work on the camera movement").** Written, linted and tested (71 pass, 16 new in `tests/motion.spec.luau`), and run for a scripted few seconds of play in a throwaway Lune harness against fake Roblox objects (no errors; the numbers below come from it). **Not yet felt in Studio.**
  - **Numbers** live in `Config/Movement` (shared: the server checks crouching with them), **maths** in `Modules/Motion` (plain numbers, so Lune tests it).
  - **The walk eases in and out** (`MovementController`). The PlayerModule's `ControlModule.moveFunction` is wrapped: each frame's input is turned into a walk that speeds up and slows down, and the Humanoid is asked for that (`Move` + `WalkSpeed`). If the hook isn't there (a PlayerModule change), it warns and falls back to easing WalkSpeed only. A mistake in the hook hands the input straight on, so you can always walk.
    - Standing → walk in 0.15 s, walk → run in 0.38 s, stopping in 0.12 s (a run carries ~0.18 s). Turning takes a beat.
    - In the air you steer at 35% (`ACCEL.air`), and let go mid-jump and your momentum carries you (`ACCEL.drift`: 16 → 14.3 studs/s over 0.3 s). A jump counts as in the air from the moment you leave the ground; just walking off a kerb or a step only after 0.12 s (`AIR_GRACE`).
    - A scripted `MoveTo` (the doorstep step-back) still walks at your walking speed: with nothing pressed, the input is handed on untouched.
  - **Sprint** (Shift / L3 / 🏃): 1.6× your walking speed, forward only (full within ~37° of where you look, none sideways or backwards; `FORWARD`). Stamina as before (17/s drain, 26/s back after 0.9 s, locked out under 30 after running dry), but only running flat out on the ground costs any (not Shift into a wall). Running dry: a gasp, then breaths you hear and see (quicker breathing, the view rises and falls with it).
  - **Crouch** (new): C toggles, Ctrl holds, B on a gamepad, 🧎 on touch (lit while crouched). Half speed, eyes at 68% of standing on a spring that settles with a little give (`CROUCH_EYE`), soft steps, a cloth rustle going down and up. Jump stands you up instead (and can't double as a jump for 0.3 s); Shift stands you up and runs. Not on a seat, ragdolled or fainted.
    - Everyone sees it: the client fires `Crouch`, the server keeps `Crouching` on the character (`CharacterService`, rate-limited). `CharacterAnimController` crouches them: hips down 40% of their height, legs out front and back (the angle that keeps the feet on the ground), leaning over, head up, short steps. Running (18–26 studs/s) they lean in and swing harder.
    - **The Knifer** hears a creeping kid only within 6 studs (`Knifer.HEAR.creep`, was 20 for any walk), and sees them lower (his sight lines aim at a crouched body and head), so cover you'd stand up over hides you. The server only believes `Crouching` while you move no faster than a crouch walk (×1.3 for lag, `Motion.creeping`).
  - **The camera** (`CameraController`) keeps time with your feet: one gait (`MovementController.gait`, phase π a step) drives the bob, the bucket and your footsteps, so each step's sound comes as the view bottoms out (checked: within one frame, walking and running).
    - The bob dips as each foot lands, sways onto the foot you're on, leans with it and nods a touch. Walking, running and creeping each have their own size (`BOB`). Running is quicker and harder but never higher: the eye averages 0.05 studs *lower* running than standing and peaks 0.02 above (breathing), and there's still no FOV kick (the user read the old one as a height change).
    - Strafing leans you into it (1.3° per walking speed). Landing drops and nods the view on a spring (a jump ~1°, a big drop more; `Motion.landingImpact`), a hard drop off a roof slows you for 0.4 s (`LANDING`; ordinary jumps don't). Jumping gives a little push-off. A ragdolled or fainted body hitting the ground isn't a landing, and whatever takes the camera over (ragdoll, jumpscare) clears the springs, so nothing plays late.
    - Only the pitch it adds stays on the camera (Roblox's camera keeps the look, rebuilds the rest), so only each frame's change in pitch is added and nothing drifts.
    - **Settings → Head bob** (new, on by default, saved like the rest): off keeps all of it small; crouching still lowers your eyes.
  - **The bucket in view** (`ViewmodelController`) swings with your steps, trails behind when you turn and catches up, is carried lower and tipped when you run, comes in close when you crouch, bounces on landing and breathes.
  - **Footsteps** (`FootstepController`): yours come from the gait (creep 0.35, walk 0.9, run 1.25 loudness), with a soft last step when you stop mid-stride. Other kids' steps are soft while they creep, and running ones are louder now (the old `> 2×` check never happened at sprint speed).
  - To check in Studio: walk/run/stop and turn while running (weight without sliding); crouch-walk under a fence line with the Knifer about; how the crouch looks to a second player; jump and drop off a porch roof; the doorstep step-back still walks you back; touch buttons; Settings → Head bob.

- **Candy bowl rework (2026-10-26, the user: "take all candy bowl (lamp breaks if u take all or sum scary to scare the player) only option take all (chance that houseowner gets out and chases u and if he catches he takes all candies pretty much the same behaviour as knifer), candy bowl should be rare it gives u candies in range(100, 300)").** Written, linted, tested (71 pass) and run in throwaway Lune harnesses (the chase against a fake street; see below). **Not yet seen in Studio.**
  - Numbers in `Config/Bowl` (mine where the user gave none).
  - **Rare:** `Bowl` weight 3 in every tier (`HouseTypes.WEIGHTS`), about one house in 30 (was 5–10). The rest went to Normal.
  - **Take it all, only:** one prompt on the bowl, *Take it all*, held 3 s (`Bowl.HOLD`, E / X). It gives a random 100–300 candy (`Bowl.CANDY`, as much as the bucket holds), and the bowl stands empty, prompt off, until the next Dawn (`HouseService.emptyBowl`, `bowlFull`); every Dawn puts every bowl out full again. The old take-one and the 35% "caught" jumpscare are gone. HUD: "TOOK IT ALL".
  - **The lamp bursts** (`DoorService` sets `LampBroken` = server time and `LampBrokenBy` on the house; `HouseVisualController`): a buzz and six flickers, a white flash, a pop with glass tinkling on the boards, 34 sparks showering down and seven bits of glass, then dark: the porch light, its glow and the Blender lantern stay out till Dawn. Played for anyone within 160 studs if it's under 3 s old (otherwise it's just dark). Whoever took it hears whispering in the house, then a low wail. Built from sounds already in the game (Overflow's glitch, KnockSingle sped up, Thud, Pop), since there's no verified glass sound.
  - **Half the time the homeowner comes out after you** (`Bowl.CHASE_CHANCE`; new `OwnerChaseService`). 1.6 s after the lamp goes, the front door flies open with a bang (`OwnerAway` on the house: every client swings it, `HouseVisualController.swingFront`) and the house's own homeowner (`OwnerModel`, rigged like a kid by `CharacterRig`, so `CharacterAnimController` walks and runs them) stands in the doorway shouting (`Bowl.SHOUTS`, over their head) for 1.1 s. Then they hunt the thief, and only the thief, the Knifer's way:
    - they see you in front of them (70 studs, 140°) with nothing in the way, not in a HideSpot, lower when you're crouched; hear you walk within 18, run within 45, creep within 6;
    - seen: they run at you at 19 (you walk 16, sprint ~26), arms out to grab (`Reaching`); lost for 3 s: to where they last saw or heard you, then the hiding places round it (the Knifer's own list of side gaps and front yards, `KniferService.lots`, and HideSpots);
    - caught (within 4 studs): you're thrown down (`RagdollService`, 2.5 s), they take back every piece of candy in your bucket (it flies out for everyone: `OwnerGrab`, `TrafficController.spill`), "GOTCHA."-style line, red at your screen's edges and a toast;
    - they go home (walk back to the door, in, and it slams shut) after a catch, when there's nowhere left to look, when you leave the street or are down, or after 50 s whatever (`CHASE.MOST`). Nobody answers that door meanwhile.
    - The thief hears the stinger as they come out and gets the chase music while they're after them (`OwnerChaseController`; `MusicController.setChase` now takes several sources, the Knifer's and theirs). Everyone hears their heavy steps.
  - **The Knifer's senses are shared now:** `src/server/AI/Hunter.luau` holds what he and the homeowners have in common (sight, hearing, walking with paths and unwedging, standing and looking round, the hiding places to search, the Humanoid set-up, the `Workspace.Hunters` folder their bodies go in). The functions moved over unchanged (diffed); each hunter brings its numbers as `rules` (`Config/Knifer`, `Config/Bowl.CHASE`).
  - **Admin:** `/chase` (the homeowner of the nearest house comes out after you), `/chase home` (everyone out goes back in); `/housetype Bowl` puts out a full bowl and mends the lamp.
  - Checked in a Lune harness running the real `OwnerChaseService` and `AI/Hunter` against a fake street (ground, a wall, a door, a scripted thief): a thief walking off in the open is caught after ~13 s, loses all 250 candy, and the homeowner walks home and the door shuts; a thief who sprints behind a wall is heard (running is loud), searched for and found; a thief who sprints off the street keeps their candy, and the homeowner gives up and goes home. No errors.
  - To check in Studio: `/housetype Bowl` by a door, hold E on the bowl: the lamp burst (sparks, glass, dark), the door flying open, the shout over their head, being chased (and the music), hiding behind a house, getting caught (candy flying, the toast), the door slamming when they're back. `/chase` for a chase without the bowl.

- **Movement, third pass (2026-10-26, the user: "add delay to the camera but only visual not actual delay… better crouching anim. Walking should be slower. More realistic jumping").** Written, linted, tested (72 pass) and run in the movement harness. **Not yet felt in Studio.**
  - **The view has weight, the aim doesn't** (`CameraController`): the picture trails where you're looking and springs back onto it (`TRAIL`: 24 rad/s, damping 0.85, at most 4° behind), while where you really look (your walk's direction, what you face, what you aim at) turns the instant you move the mouse.
    - How: Roblox's camera works each frame's look out from the last one drawn, so the turn we drew is taken off first (what's left is your real yaw and pitch), and the view is drawn from that plus the trail, the bob's nod and the landing springs. The old "add only the pitch's change" trick is folded into this.
    - Harness: a 90° flick at 180°/s trails by 3.4° at most, is back on within 0.25 s, and your look ends exactly where the mouse put it (0.003° off).
    - **Kerbs and stairs:** stepping up or down moves you at once and the view follows over a moment (`STEP`; harness: a one-stud kerb, 0.77 studs behind straight after, caught up in 0.3 s). Not in the air, and a jump of over 2.5 studs (a teleport, a fall) is followed straight away.
    - Settings → Head bob off drops the trail too.
  - **Crouching, how it looks:**
    - To everyone else (`CharacterAnimController`): down on their haunches, hips half their height lower, both legs out in front at the angle that keeps the feet on the ground, a little apart; hunched forward with the head up to look ahead; hands by the knees, tucked in. Creeping they shuffle (legs 0.3 rad either way) and rise a little with each step. Replaces the front-and-back split stance.
    - In your own view the head dips forward a touch going down and lifts coming up (`CROUCH_NOD`).
  - **Walking is slower:** speeds are shares of BaseSpeed now (`Movement.WALK` 0.7, `SPRINT` 1.6, `CROUCH` 0.4): a walk is ~11 studs/s (was 16), a run still ~26, a creep ~6. The run is unchanged on purpose, so the Knifer (chase 20) and a homeowner (19) are as easy to outrun as before; walking from them is now hopeless, which is the point. The run builds up as quickly as before (`ACCEL.sprint` 3.4 walks/s: walk → run 0.38 s). The steps are slower with it (stride by speed).
  - **Jumping:** 4 studs high (Roblox's default 7.2 was a superhero's; 4 still clears a 4.6-stud yard fence), so it's quicker too; it costs 8 stamina (out of breath, only 60% of the height); not again for 0.35 s after landing; landing from a jump slows you a touch (from 30 studs/s: `LANDING.from`). You push off with a footstep sound. To everyone else: one leg drawn up, the other trailing, the arms a little forward and out (were flung up overhead).

- **Feedback round (2026-10-26, the user: "jump is now useless", "delay on the camera… 25% lower", "take candies from the bowl till there is none in it… now u get like only 15 candy cause of low tier bucket", "car… 50% faster and two cars driving each way… with little delay one side", "skipping dialogue to left click… quick time event… only spacebar", "noise effect on camera 25% lower", "notification of the full bucket should be after u reach it", "U can knock but no answer in the houses with no light").** Linted, tested (72 pass), simulations re-run. **Not yet seen in Studio.**
  - **Jumping works again:** 6 studs (was 4), 4 stamina (was 8), and no more weak jumps when you're out of breath (after a sprint the old rule left you 2.4 studs: likely why it felt useless). Steering in the air 55% (was 35%); 0.2 s after landing before the next jump; a jump's landing no longer slows you (`LANDING.from` 55: only real drops).
  - **Camera trail a quarter less:** `TRAIL` 32 rad/s (was 24), at most 3° (was 4°). Harness: a 90° flick now trails by 2.5° at most (was 3.4°), still no drift.
  - **Grain a quarter less:** `GRAIN_TRANSPARENCY` 0.85 (was 0.8).
  - **The bowl keeps its candy:** it's put out with 100–300 in it (the bowl's `Candy` attribute, of `Full`). Each take gives as much as your bucket holds and the rest stays: empty your bucket and come back, or someone else can. Its pieces go as it empties (`HouseService.takeFromBowl`); empty, no prompt till Dawn. The prompt says how much is left, or that your bucket's full (`DoorController.applyBowl`, each player's own). The lamp bursts on the first take only; every take can bring the homeowner out. HUD: "N LEFT IN THE BOWL" / "EMPTIED THE BOWL".
  - **Cars:** half as fast again (`Traffic.SPEED` 60–72), and two each time, one each way in its own lane, the second 1.5–4 s after the first (`PAIR`, `TrafficService.pair`). The horn warns from 90 studs (about 1.3 s), and the throw is as hard as before (`KNOCK.forward` 0.6). `/car` sends the pair; `/car down|up` one.
  - **Binds:** a left click (a tap, Ⓨ on a gamepad) skips dialogue; Space, Enter and Ⓐ don't any more. Mini-games take Space on PC only (not clicks): the full-screen tap target is for touch screens only now. Ⓐ/R2 on a gamepad and taps on a touch screen still play them (they'd have nothing else). Hints say "Space / Tap / Ⓐ".
  - **Full bucket:** told the moment it fills (`CandyService.addToBucket`, a moment after the candy lands on your HUD), not when you next try a door (the doors still say "Bucket full").
  - **Dark houses take a knock:** their prompt is on ("Nobody's home..."); your knock is heard by everyone near, and nobody comes (`DoorService.knock`; knocks closer than 1.2 s together aren't sent again).

- **Feedback round 2 (2026-10-26, the user: "Jump is looking like its buggy… its still useless", "Little more delay on the camera", "Houseowner who chases blocks on the bowl", "Car the other way should be 0.5-2sec later (sometimes it appears on purpose when player is on street)", "Sometimes i cant skip dialogue", "Scrap the idea of the 3 lives HP instead. Knifer doesnt kill u one shot he deals 50hp", "Moon should be more visible on witching hour", "No matter what bucket tier u are u always have pumpkin model").** Linted, tested (73 pass), simulations re-run. **Not yet seen in Studio.**
  - **The jump's bug:** the view's kerb smoothing (`CameraController` STEP) took the first ~0.12 s of every jump for a step: the view lagged ~1.5 studs under your eyes, then snapped up 1.5 studs in one frame. Now a step leaves the view behind by an amount that dies away (`stepLag`); in the air, from the moment you jump and on the landing frame nothing is added, so a jump's view is your eyes' (harness: 0.08 studs off at most, was 1.53, 0.02 a frame, was 1.48). Walking off a ledge no longer snaps either (0.18 a frame, was 0.76). Kerbs still smooth (0.77 behind, gone in 0.3 s).
  - **Presses aren't lost:** a jump pressed up to 0.2 s too soon (coming down, or finding your feet: `JUMP.rest` now 0.1) happens as soon as it can, and one up to 0.1 s after walking off an edge still counts (`JUMP.buffer`, `JUMP.coyote`, `MovementController.jumpIfAsked`). Before, both did nothing.
  - **Camera trail a little more:** `TRAIL` 28 rad/s, 3.5° at most (was 32 and 3°): a 90° flick trails 2.8° at most (was 2.5°).
  - **Homeowners walk through bowls:** the bowl sits 2 studs in front of where they come out of the door and wedged them. Hunters (the Knifer, a homeowner) and bowls are in collision groups that don't collide (`World/CollisionGroups`, `Hunter.ghost`), and the bowl's parts carry a pass-through `PathfindingModifier` (label "Bowl", cost 6 in `Hunter.AGENT`): their paths go round it if there's room, else through.
  - **Cars:** the one the other way comes 0.5–2 s after the first (`PAIR`). One time in three (`LURK`) it waits instead, from 0.5 s on, until someone steps out into the road (off the pavement, `TrafficService.inRoad`), and comes then; nobody in 12 s and it comes anyway.
  - **Dialogue skips on any click:** a click now skips wherever it lands unless it's on a button on the screen (`DialogController.onButton`). Before, anything that had the click first (a door's prompt in the middle of the view, a panel) swallowed it. Touch still ignores taps on the thumbstick and jump button. Costume Line questions still don't skip: the server times the answer (`earliest`).
  - **Health instead of lives:** 100 health (`Config/Health`, `HealthService`: the player's `Health` attribute). The Knifer's stab takes 50 (`Knifer.DAMAGE`): the first knocks you down 1.2 s while he stands over you, and he can't stab you again for 3.5 s (`WOUND`), so get up and run; the second kills you (a ragdoll, the bucket's gone, wake at the spawn with 100). 12 s after the last hurt it comes back at 2.5 a second. The out-of-lives rule (half your banked candy) is gone with the lives. HUD: a health chip with a bar (red under 35) in place of the hearts; red from the edges when you're hurt, and a slow red pulse while low (`RunController`, milder with Reduce flashes). Data v2 drops `lives`/`livesRefillAt` (`Migrations`). Admin: `/hurt [amount]`, `/heal`. Harness: 100 → stab 50 → (regen) → stab 8 → stab dead, bucket 120 → 0, wake 100.
  - **The witching moon stands out:** red, it swells 1.7× (was 1.25×), is near solid (95%), brighter red with stronger halos, and the billboard is lit past white (`Brightness` up to 2.6) so it glows through the red haze; it goes red in 25 s (was 50).
  - **Every bucket tier carries the pumpkin:** the PlasticPumpkin mesh for all twelve tiers (`Config/Upgrades` `PUMPKIN`); only the capacity grows. The part-built models for the others stay in `Shared/Models/Buckets` until they get real art.

- **The seller (2026-10-26, the user: "Moon still is not visible because its the same color as sky on witching hour. Cars should be 25% faster. Seller spawns in one of the houses (random), he sells lockpicks, traps, (items that helps against mobs), bandage that gives u hp. HP dosent recover on itself u need to use bandage." Asked: lockpick "leave it without usage for now"; trap: "Both" (bear trap and firecracker)).** Linted, tested (76 pass), throwaway simulations of the items, the seller's nightly placement, health and the old chase/jump checks. **Not yet seen in Studio.**
  - **The witching moon isn't red on red any more:** turned, it's lit, bone pale on one side going to blood orange on the other (a `UIGradient` across the disc), with a dark rim, an orange glow (not the sky's crimson), `Brightness` 3, and 1.5× the size. It's drawn only as far out as puts it 60 studs over your eyes (80 at least), not 2000 studs off in the red fog, which washed it to the sky's colour (`MoonController`).
  - **Cars a quarter faster:** `Traffic.SPEED` 75–90 (was 60–72); the horn warns from 110 studs (still ~1.3 s); the throw is as hard as before (`KNOCK.forward` 0.48).
  - **Health doesn't come back by itself:** the regen is gone (`HealthService`, `Config/Health`); a bandage brings 50 back (`HealthService.heal(player, amount)`). A new body still has all 100.
  - **The seller:** every Dawn one house a street (any but open and bowl houses) is made house type `Seller` (`HouseService.reroll`): no knocking, badge "🏮 Seller", and his stall on the porch: him (`Items.SELLER.CHARACTER`, Owner_BagMan, a still figure in the doorway), a crate with his wares on it (a roll of bandage, a trap, firecrackers, a lockpick), a lantern you see from the street, a SELLER sign. Hunters walk through it like a bowl (`CollisionGroups.PORCH`, pass-through "Porch" pathfinding cost). The crate's **Browse** prompt (tag `SellerStall`) opens his window (`SellerController`): a line from him, then a row a thing (what it does, how many you've got of how many you can carry, its price here); walk off and it closes. `/housetype Seller` puts him at the nearest house.
  - **His things** (`Config/Items`; `ItemService` buys and uses; bought with banked candy, kept between runs in `consumables`). Prices are the street's doors' worth (`Items.price`: `doors` × the street's average door, so 40 for a bandage on Cardboard Court, 120 on Maple Lane):
    - 🩹 **Bandage** (8 doors, carry 5): +50 health; not if you're not hurt.
    - 🪤 **Bear trap** (14, carry 3): set at your feet, 3 out at once, gone after 5 min. A hunter (the Knifer, a homeowner after you) whose feet come within 2.4 studs is held 5 s (`HeldUntil`; `Hunter.held` stands them still in both services' `think`): the jaws snap shut and you're told "🪤 Your trap caught the Knifer!".
    - 🧨 **Firecracker** (10, carry 5): thrown 26 studs along where you look (short of a wall), fizzes 1.3 s, bangs 5 s. Every hunter within 120 studs while it bangs goes to it (state investigate, `lastKnown` = it) and sees and hears no one till 7 s after the first bang (`LuredTo`/`LuredUntil`, `Hunter.lure` in `sees`/`hears`); then they search round it.
    - 🗝️ **Lockpick** (12, carry 3): no use yet (the user's call); using it says so and keeps it.
  - **The bar** (`ItemsController`): bottom-centre slots for what you've got (icon, ×count, key), keys 1–4 (d-pad left/down/right on a gamepad, tap on a touch screen), only in a run. Sounds (stand-ins from what we have): the bandage's cloth, the trap set (`Latch`) and its steel snap (`CarHit` pitched up), the firecracker thrown (`Whoosh`, an arc drawn locally), its fuse sparks, and bangs (`Slap` sharp + `Thunder` sped up) with flashes and sparks. Real firecracker and trap recordings would be better.
  - **Admin:** `/item <Bandage|BearTrap|Firecracker|Lockpick|all> [count]` (free, up to what you can carry), `/housetype Seller`.
  - Simulated: buying (too far, his price, carry limit, too poor), the bandage (not hurt / +50 / cooldown), traps (the 4th refused, a hunter on one held 5 s, sprung, owner told, gone after), the firecracker (lands 26 ahead or short of a wall, near hunter lured, far one not, gone after), the lockpick, and three nights of rerolls (one seller a street each night, moved, old stalls gone, his door unknockable).
  - *(Reworked the same day, below: no stall, he answers his door.)*

- **The seller answers his door (2026-10-27, the user: "the seller should work like a normal houseowner he opens the door and menu shows. He needs his own set of animations. if u cant make quality animations now just leave default homeowner ones").** Linted, tested (76 pass), simulated. **Not yet seen in Studio.**
  - **He lives there:** the seller's house is his (its `OwnerModel` is `Items.SELLER.CHARACTER`, Owner_BagMan, taken out of the homeowners' cast so he's only ever the seller; if his meshes aren't in the place, whoever lives there sells). The porch stall is gone; a lantern hangs by his door so you can pick his house out (`HouseService.hangLantern`), and the badge says 🏮 Seller. Made a normal house again (`/housetype`), someone else moves back in.
  - **Knock** (the door says "Knock · Seller", a full bucket can knock: no candy here, no cooldown): he comes to the door like any homeowner, the same figure, walk and **default homeowner animations** (as the user allowed; his own set can come once they can be seen in Studio), always the *Waiting* entrance (the door opens and he's already standing in the dark hall: `HomeownerService.appear(..., style)`), says one of his lines, and once he's out (`OUT_AFTER`) his window opens (`SellerOpen`) with your view on him as at any door (`DoorController.faceHouse`).
  - **Close the window, walk off (16 studs), or a new night** and he says goodbye ("Come back alive.", `Items.SELLER.BYE`), bows/waves/nods and goes back in once it's said (`SellerDone`, `DoorService.sellerDone`). Buying needs him out and you within 16 studs of his door (`ItemService`).
  - Simulated (DoorService on a virtual clock): knock → he comes (Waiting) → hello → window at 2.5 s; knocking again while it's open does nothing; closing it → goodbye, back in after the line; walking off → the same; three nights of rerolls (he moves house each night, only his houses have him and a lantern; made Normal, someone else lives there); buying refused when he's gone back in or it isn't his house.

- **Look (reworked 2026-10-23, the user found everything too dark):** the moon hangs ~40° up over the far end of each street (`World.LIGHTING.latitude` -26.5 at midnight), brighter cool moonlit ambient per street (later streets darker), exposure +0.4, light grade (saturation -0.12, contrast 0.08), depth of field only far away, and a shadowless cool `MoonFill_<house>` light over each lot's sidewalk, because the low moon throws each house's shadow over the next yard. Faint scanlines; grain off. *(The flashlight was deleted on 2026-10-25: the user wants none in the game. PROMPT's Flashlight upgrade track is dropped.)* Recommended manual step: Lighting → Technology = Future (MCP can't set it).

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

- **From the user's big list, not done yet** (they'll send these as separate prompts):
  - Door levels: a door opened 3 times upgrades; 3 levels with new characters, harder games, more candy.
  - More homeowner interactions (peeking through the door, etc.).
  - The yard chase: entering a plot closes the gate behind you, a homeowner chases you with a knife, the rest of the map goes black, and you hide in a backyard bush. Needs a Blender bush and knife.
  - A run-and-hide monster event every 10 min (no model yet).
  - ~~A car driving the streets~~: done 2026-10-26, waiting on the user to import `Car.fbx` (see "The car").
  - "More addictive" as a whole.
  - Then the open-house heists (Phase 3).

0. **Phase 3 · Heists** (PROMPT §3.9): interiors per style, loot spots, server-side noise, crouch/sprint, Homeowner AI, caught/escape, house lockout, safe-cracking.
1. The user asked for proof that real models are possible, then to continue with the plan ("give me one high quality model … and continue with the prompt"). Done (the pumpkin bucket). **From now on every feature ships with real art, juicy UI and sound** (see the memory note). The remaining 11 bucket tiers, houses and props are modelled in Blender as each phase touches them (AI meshes were rejected for houses).
2. **Checkpoint A** (user, 10 min, fresh profile; the test profile was reset): Studio → Play →
   1. walk through the CARDBOARD COURT arch, press **E** at a door, stop the needle in the green (Space/click/tap) → candy flies into the bucket;
   2. fill the bucket (see OVERFLOW), stand in a glowing **Candy Box** circle to stash;
   3. **Shop**: buy the Plastic Pumpkin (AI mesh in your hand), Charm, Sneakers;
   4. reach 150 → unlock **Maple Lane** at the gate at the end of the street; try a 🚌 bus stop;
   5. report anything that feels slow, ugly or confusing.
   Phase 2 started in parallel (the user said to continue).
