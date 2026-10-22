--!strict
-- Knock on a door → mini-game → candy into the bucket → per-player cooldown on that house.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Minigames = require(ReplicatedStorage.Shared.Config.Minigames)
local Neighborhoods = require(ReplicatedStorage.Shared.Config.Neighborhoods)
local Formulas = require(ReplicatedStorage.Shared.Modules.Formulas)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local Rng = require(ReplicatedStorage.Shared.Modules.Rng)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)
local MinigameService = require(script.Parent.MinigameService)
local NotifyService = require(script.Parent.NotifyService)
local WorldService = require(script.Parent.WorldService)

export type DoorResult = {
	houseId: string,
	grade: string,
	amount: number, -- candy the door gave
	added: number, -- what fit in the bucket
	overflow: number, -- what was lost
	cooldownUntil: number, -- workspace:GetServerTimeNow() when the door is ready again
}

local DoorService = {}

local cooldowns: { [Player]: { [string]: number } } = {}
local random = Random.new()
local rng = Rng.new(random:NextInteger(1, 2147483646))

local function pickMinigame(neighborhood: Neighborhoods.Neighborhood): string
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
	return if readyAt then readyAt - Workspace:GetServerTimeNow() else 0
end

local function finish(player: Player, houseId: string, grade: string?)
	if grade == nil or player.Parent ~= Players then
		return -- abandoned: no reward, no cooldown, they can knock again
	end
	local house = WorldService.getHouse(houseId)
	local data = DataService.get(player)
	local neighborhood = house and Neighborhoods.byId[house.neighborhood]
	if house == nil or data == nil or neighborhood == nil then
		return
	end

	local base = random:NextNumber(neighborhood.candy.min, neighborhood.candy.max)
	local amount =
		Formulas.doorCandy(base, grade, 0, CandyService.bonuses(player), CandyService.eventMultiplier(player))
	local added, overflow = CandyService.addToBucket(player, amount)

	local readyAt = Workspace:GetServerTimeNow() + Economy.DOOR_COOLDOWN
	local list = cooldowns[player]
	if list then
		list[houseId] = readyAt
	end
	DataService.mutate(player, "stats", function(stats)
		stats.doors += 1
		if grade == "PERFECT" then
			stats.perfects += 1
		end
	end)

	local result: DoorResult = {
		houseId = houseId,
		grade = grade,
		amount = amount,
		added = added,
		overflow = overflow,
		cooldownUntil = readyAt,
	}
	Net.event("DoorResult"):FireClient(player, result)
end

local function knock(player: Player, houseId: string)
	local house = WorldService.getHouse(houseId)
	local data = DataService.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if house == nil or data == nil or root == nil then
		return
	end
	if MinigameService.isBusy(player) then
		return
	end
	if not data.neighborhoods[house.neighborhood] then
		return
	end
	if (root.Position - house.door.Position).Magnitude > Economy.DOOR_RANGE then
		return
	end
	local wait = cooldownLeft(player, houseId)
	if wait > 0 then
		NotifyService.send(player, `💤 Nobody's answering yet. Come back in {math.ceil(wait)}s`, "info")
		return
	end
	local neighborhood = Neighborhoods.byId[house.neighborhood]
	local difficulty = math.clamp(neighborhood.tier, Minigames.DIFFICULTY_MIN, Minigames.DIFFICULTY_MAX)
	MinigameService.issue(player, pickMinigame(neighborhood), difficulty, function(grade)
		finish(player, houseId, grade)
	end, { houseId = houseId })
end

function DoorService.Start()
	for houseId, house in WorldService.info().houses do
		house.prompt.Triggered:Connect(function(player)
			knock(player, houseId)
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		cooldowns[player] = {}
	end)
	for _, player in Players:GetPlayers() do
		cooldowns[player] = cooldowns[player] or {}
	end
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)
end

return DoorService
