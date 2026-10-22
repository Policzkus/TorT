--!strict
-- Owns every player's saved data (ProfileStore: session locking, autosave, shutdown saves).
-- Read with DataService.get. Write ONLY through set / increment / mutate so changes are
-- batched and synced to that player's client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Types = require(Shared.Modules.Types)

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local Template = require(script.Parent.Parent.Data.Template)
local Migrations = require(script.Parent.Parent.Data.Migrations)

type PlayerData = Types.PlayerData

local DataService = {}

DataService.Loaded = Signal.new() -- (player: Player, data: PlayerData)
DataService.Changed = Signal.new() -- (player: Player, key: string, value: any)

local store: any = nil
local profiles: { [Player]: any } = {}
local dirty: { [Player]: { [string]: boolean } } = {}

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function sendFull(player: Player)
	local profile = profiles[player]
	if profile then
		Net.event("StateSync"):FireClient(player, profile.Data, true)
	end
end

local function flush()
	local stateSync = Net.event("StateSync")
	for player, keys in dirty do
		if next(keys) == nil then
			continue
		end
		local profile = profiles[player]
		if profile then
			local changes = {}
			for key in keys do
				changes[key] = profile.Data[key]
			end
			stateSync:FireClient(player, changes, false)
		end
		table.clear(keys)
	end
end

local function loadPlayer(player: Player)
	local profile = store:StartSessionAsync(GameConfig.DATA_KEY_PREFIX .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			player:Kick("We couldn't load your candy. Please rejoin! (data error)")
		end
		return
	end

	local result = Migrations.apply(profile.Data)
	if result == "future" then
		-- Saved by a newer server. Leave it untouched so nothing gets downgraded.
		profile:EndSession()
		player:Kick("This server is out of date. Please rejoin to get the latest version!")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		-- If we still own this entry, the session was taken away (e.g. joined another server).
		if profiles[player] == profile then
			profiles[player] = nil
			dirty[player] = nil
			if player.Parent == Players then
				player:Kick("Your data was loaded on another server. Please rejoin.")
			end
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local data: PlayerData = profile.Data
	local now = os.time()
	if data.firstJoin == 0 then
		data.firstJoin = now
	end
	data.lastJoin = now

	profiles[player] = profile
	dirty[player] = {}
	print(
		`[Data] Loaded {player.Name} ({result}, session #{profile.SessionLoadCount}, store {ProfileStore.DataStoreState})`
	)
	DataService.Loaded:Fire(player, data)
	sendFull(player)
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	dirty[player] = nil
	if profile then
		profile:EndSession()
	end
end

-- Public API -------------------------------------------------------------------------------

function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Yields until the player's data is loaded (or they leave / time out).
function DataService.waitFor(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return DataService.get(player)
end

-- Call after changing a nested table in place (or use mutate).
function DataService.markDirty(player: Player, key: string)
	local keys = dirty[player]
	local profile = profiles[player]
	if keys == nil or profile == nil then
		return
	end
	keys[key] = true
	DataService.Changed:Fire(player, key, profile.Data[key])
end

function DataService.set(player: Player, key: string, value: any)
	local data = DataService.get(player) :: any
	if data == nil then
		return
	end
	assert((Template :: any)[key] ~= nil, `Unknown data key '{key}'`)
	data[key] = value
	DataService.markDirty(player, key)
end

-- For top-level numbers (candy, souls...). Returns the new value, or nil if not loaded.
function DataService.increment(player: Player, key: string, delta: number): number?
	local data = DataService.get(player) :: any
	if data == nil then
		return nil
	end
	assert(type(data[key]) == "number", `Data key '{key}' is not a number`)
	data[key] += delta
	DataService.markDirty(player, key)
	return data[key]
end

-- For top-level tables: mutate(player, "stats", function(stats) stats.doors += 1 end)
function DataService.mutate(player: Player, key: string, fn: (value: any) -> ())
	local data = DataService.get(player) :: any
	if data == nil then
		return
	end
	assert(type(data[key]) == "table", `Data key '{key}' is not a table`)
	fn(data[key])
	DataService.markDirty(player, key)
end

-- Admin/testing: wipe back to a fresh profile. Purchase receipts and first-join time survive.
function DataService.reset(player: Player)
	local data = DataService.get(player) :: any
	if data == nil then
		return
	end
	for key, value in Template :: any do
		if key ~= "purchases" and key ~= "firstJoin" then
			data[key] = deepCopy(value)
		end
	end
	data.lastJoin = os.time()
	for key in Template :: any do
		DataService.markDirty(player, key)
	end
	sendFull(player)
end

-- Forces an immediate save (normally ProfileStore autosaves and saves on leave/shutdown).
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Save()
	end
end

-- Receipt handling (Phase 6) needs the profile itself (LastSavedData, OnAfterSave).
function DataService.getProfile(player: Player): any
	return profiles[player]
end

-- Lifecycle ---------------------------------------------------------------------------------

function DataService.Init()
	local baseStore = ProfileStore.New(GameConfig.DATA_STORE_NAME, Template)
	local useMock = RunService:IsStudio() and GameConfig.USE_MOCK_DATA_IN_STUDIO
	store = if useMock then baseStore.Mock else baseStore

	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		warn(`[Data] ProfileStore error ({storeName}/{profileKey}): {message}`)
	end)
	ProfileStore.OnCriticalToggle:Connect(function(isCritical)
		warn(`[Data] DataStore critical state: {isCritical}`)
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerRemoving:Connect(releasePlayer)

	Net.connect("StateRequest", function(player)
		sendFull(player)
	end, { rate = 0.2, burst = 3 })

	task.spawn(function()
		while true do
			task.wait(GameConfig.STATE_FLUSH_INTERVAL)
			flush()
		end
	end)

	-- Server-only stat; not synced every tick.
	task.spawn(function()
		while true do
			task.wait(GameConfig.PLAYTIME_TICK)
			for _, profile in profiles do
				profile.Data.stats.playtime += GameConfig.PLAYTIME_TICK
			end
		end
	end)

	task.spawn(function()
		local deadline = os.clock() + 40 -- ProfileStore retries transient Roblox errors for a while
		while ProfileStore.DataStoreState == "NotReady" and os.clock() < deadline do
			task.wait(0.5)
		end
		local state = ProfileStore.DataStoreState
		if state == "Access" then
			print("[Data] DataStore access OK - progress will save")
		else
			warn(
				`[Data] DataStore state is '{state}' - progress will NOT save. In Studio: publish the place and`
					.. " enable Game Settings > Security > Enable Studio Access to API Services."
			)
		end
	end)
end

return DataService
