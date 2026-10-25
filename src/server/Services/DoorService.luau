--!strict
-- Knock on a door → mini-game → candy into the bucket → per-player cooldown on that house.
-- Also the Take-One Bowls (take one safely, or hold TAKE ALL and maybe get caught).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Homeowners = require(ReplicatedStorage.Shared.Config.Homeowners)
local HouseTypes = require(ReplicatedStorage.Shared.Config.HouseTypes)
local Minigames = require(ReplicatedStorage.Shared.Config.Minigames)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Formulas = require(ReplicatedStorage.Shared.Modules.Formulas)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local HomeownerService = require(script.Parent.HomeownerService)
local HouseService = require(script.Parent.HouseService)
local MinigameService = require(script.Parent.MinigameService)
local NotifyService = require(script.Parent.NotifyService)
local WorldEventsService = require(script.Parent.WorldEventsService)
local WorldService = require(script.Parent.WorldService)

export type DoorResult = {
	houseId: string,
	grade: string,
	amount: number, -- candy the door gave
	added: number, -- what fit in the bucket
	overflow: number, -- what was lost to a full bucket
	cooldownUntil: number, -- workspace:GetServerTimeNow() when the door is ready again
	houseType: string,
	streak: number, -- Sweet Streak after this door
	brave: boolean, -- held through a trick house's Nerve Hold
	fullSize: boolean, -- got the Full-Size Bar ×10
	event: number, -- event multiplier applied (Witching Hour, Blood Moon)
	liked: boolean?, -- the homeowner's preference matched your costume's tag
	costumed: boolean?, -- false: no costume, so the homeowner barely gave anything
	bowl: string?, -- "one" | "all" | "caught"
	lost: number?, -- candy lost when caught
}

local CAUGHT_LINES = {
	"THOSE ARE FOR THE TRICK-OR-TREATERS!",
	"HEY! ONE PER KID!",
	"I SAW THAT, YOU LITTLE GOBLIN!",
	"GIMME BACK MY CANDY!",
}

local DoorService = {}

local cooldowns: { [Player]: { [string]: number } } = {}
local streaks: { [Player]: number } = {}
local random = Random.new()
local rng = Rng.new(random:NextInteger(1, 2147483646))

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function pickMinigame(neighborhood: Neighborhoods.Neighborhood, houseType: string): string
	if houseType == "Trick" then
		return "NerveHold" -- trick houses always test your nerve
	end
	local weights = {}
	for kind, weight in neighborhood.minigames do
		if MinigameService.isAvailable(kind) then
			weights[kind] = weight
		end
	end
	return rng:weighted(weights) or "TimingBar"
end

local function cooldownLeft(player: Player, houseId: string): number
	local list = cooldowns[player]
	local readyAt = list and list[houseId]
	return if readyAt then readyAt - now() else 0
end

local function startCooldown(player: Player, houseId: string): number
	local readyAt = now() + Economy.DOOR_COOLDOWN
	local list = cooldowns[player]
	if list then
		list[houseId] = readyAt
	end
	return readyAt
end

local function nearHouse(player: Player, houseId: string, range: number?): boolean
	local house = WorldService.getHouse(houseId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return house ~= nil
		and root ~= nil
		and (root.Position - house.door.Position).Magnitude <= (range or Economy.DOOR_RANGE)
end

-- Shared checks for knocking and bowls. Returns the house and its street config if allowed.
local function canVisit(player: Player, houseId: string): (any, Neighborhoods.Neighborhood?)
	local house = WorldService.getHouse(houseId)
	local data = DataService.get(player)
	if house == nil or data == nil or not data.neighborhoods[house.neighborhood] then
		return nil, nil
	end
	if MinigameService.isBusy(player) or not nearHouse(player, houseId) then
		return nil, nil
	end
	local wait = cooldownLeft(player, houseId)
	if wait > 0 then
		NotifyService.send(player, `💤 Nobody's answering yet. Come back in {math.ceil(wait)}s`, "info")
		return nil, nil
	end
	return house, Neighborhoods.byId[house.neighborhood]
end

local function updateStreak(player: Player, grade: string): number
	local streak = streaks[player] or 0
	if Formulas.isGoodGrade(grade) then
		streak += 1
	elseif grade == "MISS" then
		streak = 0
	end
	streaks[player] = streak
	return streak
end

local function finish(player: Player, houseId: string, houseType: string, grade: string?)
	if grade == nil or player.Parent ~= Players then
		return -- abandoned: no reward, no cooldown, they can knock again
	end
	local house = WorldService.getHouse(houseId)
	local neighborhood = house and Neighborhoods.byId[house.neighborhood]
	if house == nil or neighborhood == nil or DataService.get(player) == nil then
		return
	end

	local brave = houseType == "Trick" and grade ~= "MISS"
	local typeMultiplier = if houseType == "Trick"
		then (if brave then HouseTypes.CANDY.Trick else 1)
		else HouseTypes.CANDY[houseType] or 1
	local fullSize = WorldEventsService.claimFullSize(player, houseId)
	local streak = updateStreak(player, grade)
	local event = CandyService.eventMultiplier(player)
	local base = random:NextNumber(neighborhood.candy.min, neighborhood.candy.max) * typeMultiplier * fullSize
	local bonuses = CandyService.bonuses(player)
	local costume = CandyService.costume(player)
	local liked = costume ~= nil and costume.tag == HouseService.preference(houseId)
	if liked then
		bonuses.preference = HouseTypes.PREFERENCE_BONUS
	end
	local amount = Formulas.doorCandy(base, grade, Formulas.streakBonus(streak), bonuses, event)
	local added, overflow = CandyService.addToBucket(player, amount)
	local readyAt = startCooldown(player, houseId)

	DataService.mutate(player, "stats", function(stats)
		stats.doors += 1
		if grade == "PERFECT" then
			stats.perfects += 1
		end
		stats.bestStreak = math.max(stats.bestStreak, streak)
	end)

	local result: DoorResult = {
		houseId = houseId,
		grade = grade,
		amount = amount,
		added = added,
		overflow = overflow,
		cooldownUntil = readyAt,
		houseType = houseType,
		streak = streak,
		brave = brave,
		fullSize = fullSize > 1,
		event = event,
		liked = liked,
		costumed = costume ~= nil,
	}
	Net.event("DoorResult"):FireClient(player, result)
	if fullSize > 1 then
		NotifyService.others(player, `🍫 {player.DisplayName} grabbed a FULL-SIZE BAR!`, "rare")
	end
end

local function knock(player: Player, houseId: string)
	local houseType = HouseService.houseType(houseId)
	if houseType == "LightsOff" or houseType == "Bowl" or houseType == "Open" then
		return -- nobody answers
	end
	local house, neighborhood = canVisit(player, houseId)
	if house == nil or neighborhood == nil then
		return
	end
	local difficulty = neighborhood.tier
		+ (HouseTypes.DIFFICULTY[houseType] or 0)
		+ WorldEventsService.difficultyBonus()
	difficulty = math.clamp(difficulty, Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	local kind = pickMinigame(neighborhood, houseType)
	-- They come out and say hello before the mini-game starts (Costume Line's question is its
	-- hello): the challenge's intro, which the client plays out and the clock leaves out.
	local outIn = HomeownerService.appear(houseId)
	local intro = outIn + (if kind == "CostumeLine" then 0 else Homeowners.HELLO_TIME)
	local context = {
		houseId = houseId,
		personality = HouseService.owner(houseId),
		houseType = houseType,
		outIn = outIn,
		door = house.door.Position, -- the client calls the visit off if you walk away from it
	}
	local issued = MinigameService.issue(player, kind, difficulty, function(grade)
		HomeownerService.leave(houseId)
		finish(player, houseId, houseType, grade)
		-- Every Nerve Hold ends with the jumpscare (the client tones it down per Settings).
		if grade and kind == "NerveHold" then
			Net.event("Jumpscare"):FireClient(player, houseId, "monster")
		end
	end, context, intro)
	if issued == nil then
		HomeownerService.leave(houseId)
		return
	end
	-- Walk away while they're coming out, or mid-game, and it's off (the client usually says so first).
	task.spawn(function()
		while MinigameService.isOpen(player, issued.id) do
			if not nearHouse(player, houseId, Economy.DOOR_LEAVE) then
				MinigameService.cancel(player)
				Net.event("MinigameCancelled"):FireClient(player, issued.id)
				break
			end
			task.wait(0.25)
		end
	end)
end

local function takeFromBowl(player: Player, houseId: string, mode: string)
	if HouseService.houseType(houseId) ~= "Bowl" then
		return
	end
	local house, neighborhood = canVisit(player, houseId)
	if house == nil or neighborhood == nil then
		return
	end
	local readyAt = startCooldown(player, houseId)
	local result: DoorResult = {
		houseId = houseId,
		grade = "GOOD",
		amount = 0,
		added = 0,
		overflow = 0,
		cooldownUntil = readyAt,
		houseType = "Bowl",
		streak = streaks[player] or 0,
		brave = false,
		fullSize = false,
		event = CandyService.eventMultiplier(player),
		bowl = mode,
	}

	if mode == "all" and random:NextNumber() < HouseTypes.BOWL_CAUGHT_CHANCE then
		local lost = CandyService.loseFromBucket(player, HouseTypes.CAUGHT_LOSS)
		DataService.mutate(player, "stats", function(stats)
			stats.caught += 1
		end)
		result.bowl = "caught"
		result.lost = lost
		Net.event("Jumpscare"):FireClient(player, houseId, "caught", CAUGHT_LINES[random:NextInteger(1, #CAUGHT_LINES)])
		Net.event("DoorResult"):FireClient(player, result)
		return
	end

	local multiplier = if mode == "all" then HouseTypes.BOWL_TAKE_ALL else HouseTypes.BOWL_TAKE_ONE
	local base = random:NextNumber(neighborhood.candy.min, neighborhood.candy.max) * multiplier
	local amount = Formulas.doorCandy(base, "GOOD", 0, CandyService.bonuses(player), result.event)
	local added, overflow = CandyService.addToBucket(player, amount)
	result.amount, result.added, result.overflow = amount, added, overflow
	if mode == "all" then
		result.grade = "PERFECT"
	end
	Net.event("DoorResult"):FireClient(player, result)
end

function DoorService.resetCooldowns()
	for _, list in cooldowns do
		table.clear(list)
	end
	Net.event("CooldownsReset"):FireAllClients()
end

function DoorService.streak(player: Player): number
	return streaks[player] or 0
end

function DoorService.Start()
	for houseId, house in WorldService.info().houses do
		house.prompt.Triggered:Connect(function(player)
			knock(player, houseId)
		end)
	end
	HouseService.BowlTriggered:Connect(takeFromBowl)
	WorldEventsService.NightStarted:Connect(function(night: number)
		if night > 1 then
			DoorService.resetCooldowns()
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		cooldowns[player] = {}
	end)
	for _, player in Players:GetPlayers() do
		cooldowns[player] = cooldowns[player] or {}
	end
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
		streaks[player] = nil
	end)
end

return DoorService
