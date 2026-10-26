--!strict
-- The Witching Hour, Full-Size Bar houses and the Blood Moon (PROMPT §3.4). There are no Nights: the
-- Witching Hour comes round every Events.WITCHING_EVERY seconds for WITCHING_LENGTH, and when it
-- ends the town changes (WitchingEnded: house types reroll). State is replicated as attributes on
-- ReplicatedStorage.WorldState so clients can draw the countdown, the red sky and the gold beam:
--   Witching, WitchingAt (server time it next starts, or started), WitchingEndsAt, BloodMoon,
--   FullSizeHouse ("" = none), FullSizeEndsAt, FullSizePosition (the door, so the beam shows even
--   if the house isn't streamed in)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Mode = require(ReplicatedStorage.Shared.Modules.Mode)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local NotifyService = require(script.Parent.NotifyService)
local WorldService = require(script.Parent.WorldService)

local WorldEventsService = {}

WorldEventsService.WitchingStarted = Signal.new()
WorldEventsService.WitchingEnded = Signal.new()

local state: Folder
local random = Random.new()
local nextFullSizeAt = 0
local fullSizeVisitors: { [Player]: boolean } = {}
local fullSizeCount = 0
local warned = false
local bloodMoonOverride: boolean? = nil -- admin testing
-- House types that can become the Full-Size Bar house (set by HouseService to avoid a cycle).
local canHostFullSize: (houseId: string) -> boolean = function(_houseId: string)
	return true
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

function WorldEventsService.state(): Folder
	return state
end

function WorldEventsService.isWitching(): boolean
	return state:GetAttribute("Witching") == true
end

function WorldEventsService.isBloodMoon(): boolean
	return state:GetAttribute("BloodMoon") == true
end

-- Product of active event multipliers, capped (PROMPT §3.7).
function WorldEventsService.eventMultiplier(): number
	local multiplier = 1
	if WorldEventsService.isWitching() then
		multiplier *= Events.WITCHING_CANDY
	end
	if WorldEventsService.isBloodMoon() then
		multiplier *= Events.BLOOD_MOON_CANDY
	end
	return math.min(multiplier, Economy.EVENT_MULTIPLIER_CAP)
end

function WorldEventsService.difficultyBonus(): number
	return if WorldEventsService.isWitching() then Events.WITCHING_DIFFICULTY else 0
end

function WorldEventsService.setFullSizeFilter(filter: (houseId: string) -> boolean)
	canHostFullSize = filter
end

function WorldEventsService.fullSizeHouse(): string?
	local id = state:GetAttribute("FullSizeHouse")
	return if type(id) == "string" and id ~= "" then id else nil
end

-- The multiplier this player gets at this house right now (×10 for the first visitors, once each).
function WorldEventsService.claimFullSize(player: Player, houseId: string): number
	if WorldEventsService.fullSizeHouse() ~= houseId or fullSizeVisitors[player] then
		return 1
	end
	if fullSizeCount >= Events.FULL_SIZE_VISITORS then
		return 1
	end
	fullSizeVisitors[player] = true
	fullSizeCount += 1
	if fullSizeCount >= Events.FULL_SIZE_VISITORS then
		task.delay(1, WorldEventsService.endFullSize)
	end
	return Events.FULL_SIZE_MULTIPLIER
end

function WorldEventsService.endFullSize()
	if WorldEventsService.fullSizeHouse() then
		state:SetAttribute("FullSizeHouse", "")
		state:SetAttribute("FullSizeEndsAt", 0)
	end
	table.clear(fullSizeVisitors)
	fullSizeCount = 0
	nextFullSizeAt = now() + Events.FULL_SIZE_INTERVAL + random:NextNumber(-1, 1) * Events.FULL_SIZE_JITTER
end

-- Picks a house on a street someone is standing on. Returns false if nobody is out trick-or-treating.
function WorldEventsService.startFullSize(): boolean
	local occupied: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local zone = player:GetAttribute("Zone")
		if type(zone) == "string" and Neighborhoods.byId[zone] then
			occupied[zone] = true
		end
	end
	local candidates = {}
	for houseId, house in WorldService.info().houses do
		if occupied[house.neighborhood] and canHostFullSize(houseId) then
			table.insert(candidates, house)
		end
	end
	if #candidates == 0 then
		return false
	end
	local house = candidates[random:NextInteger(1, #candidates)]
	table.clear(fullSizeVisitors)
	fullSizeCount = 0
	state:SetAttribute("FullSizeHouse", house.id)
	state:SetAttribute("FullSizePosition", house.door.Position)
	state:SetAttribute("FullSizeEndsAt", now() + Events.FULL_SIZE_DURATION)
	local street = Neighborhoods.byId[house.neighborhood]
	NotifyService.all(
		`🍫 A FULL-SIZE BAR house appeared on {street.name}! First {Events.FULL_SIZE_VISITORS} get ×10!`,
		"rare"
	)
	return true
end

-- The Witching Hour, now (and the next one WITCHING_EVERY after it ends).
function WorldEventsService.startWitching()
	if WorldEventsService.isWitching() then
		return
	end
	state:SetAttribute("Witching", true)
	state:SetAttribute("WitchingAt", now())
	state:SetAttribute("WitchingEndsAt", now() + Events.WITCHING_LENGTH)
	NotifyService.all("🩸 THE WITCHING HOUR HAS BEGUN! ×2 candy, but the houses are scarier...", "error")
	WorldEventsService.WitchingStarted:Fire()
end

function WorldEventsService.endWitching()
	if not WorldEventsService.isWitching() then
		return
	end
	state:SetAttribute("Witching", false)
	state:SetAttribute("WitchingAt", now() + Events.WITCHING_EVERY)
	state:SetAttribute("WitchingEndsAt", 0)
	warned = false
	NotifyService.all("The Witching Hour is over. The town has changed...", "info")
	WorldEventsService.WitchingEnded:Fire()
end

local function tick()
	if WorldEventsService.isWitching() then
		if now() >= (state:GetAttribute("WitchingEndsAt") :: number) then
			WorldEventsService.endWitching()
		end
	else
		local startsIn = (state:GetAttribute("WitchingAt") :: number) - now()
		if not warned and startsIn <= Events.WITCHING_WARNING then
			warned = true
			NotifyService.all("⚠ The Witching Hour starts in 1 minute...", "info")
		end
		if startsIn <= 0 then
			WorldEventsService.startWitching()
		end
	end

	local unix = os.time()
	local bloodMoon = unix >= Events.BLOOD_MOON_START and unix < Events.BLOOD_MOON_END
	if bloodMoonOverride ~= nil then
		bloodMoon = bloodMoonOverride
	end
	if state:GetAttribute("BloodMoon") ~= bloodMoon then
		state:SetAttribute("BloodMoon", bloodMoon)
		if bloodMoon then
			NotifyService.all("🌕🩸 THE BLOOD MOON HAS RISEN! ×2 candy all Halloween!", "rare")
		end
	end

	local fullSize = WorldEventsService.fullSizeHouse()
	if fullSize and now() >= (state:GetAttribute("FullSizeEndsAt") :: number) then
		WorldEventsService.endFullSize()
	elseif fullSize == nil and now() >= nextFullSizeAt then
		if not WorldEventsService.startFullSize() then
			nextFullSizeAt = now() + 15 -- nobody out yet; try again soon
		end
	end
end

-- Admin: force the Blood Moon on/off (nil = follow the calendar).
function WorldEventsService.setBloodMoonOverride(value: boolean?)
	bloodMoonOverride = value
end

function WorldEventsService.Init()
	state = Instance.new("Folder")
	state.Name = "WorldState"
	state:SetAttribute("Witching", false)
	state:SetAttribute("WitchingAt", now() + Events.WITCHING_EVERY)
	state:SetAttribute("WitchingEndsAt", 0)
	state:SetAttribute("BloodMoon", false)
	state:SetAttribute("FullSizeHouse", "")
	state:SetAttribute("FullSizeEndsAt", 0)
	state.Parent = ReplicatedStorage
	nextFullSizeAt = now() + Events.FULL_SIZE_INTERVAL / 2
end

function WorldEventsService.Start()
	if Mode.isLobby() then
		return -- no events in the lobby
	end
	Players.PlayerRemoving:Connect(function(player)
		fullSizeVisitors[player] = nil
	end)
	while true do
		task.wait(1)
		tick()
	end
end

return WorldEventsService
