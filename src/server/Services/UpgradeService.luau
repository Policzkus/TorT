--!strict
-- Sweet Tooth's Shop upgrade purchases (PROMPT §3.12) and their effects on the character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Formulas = require(ReplicatedStorage.Shared.Modules.Formulas)
local Net = require(ReplicatedStorage.Shared.Modules.Net)
local CandyService = require(script.Parent.CandyService)
local DataService = require(script.Parent.DataService)

local UpgradeService = {}

local function applyMovement(player: Player)
	local data = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if data and humanoid then
		humanoid.WalkSpeed = Formulas.walkSpeed(data.upgrades.sneakers)
	end
end

local function describe(trackId: string, newLevel: number): string
	local track = Formulas.track(trackId)
	if track.kind == "tiers" then
		return `{track.icon} {Formulas.bucketTier(newLevel).name} unlocked!`
	end
	return `{track.icon} {track.name} level {newLevel}!`
end

-- Returns (ok, message).
function UpgradeService.buy(player: Player, trackId: any): (boolean, string)
	if type(trackId) ~= "string" or Upgrades.tracks[trackId] == nil then
		return false, "That upgrade doesn't exist"
	end
	local data = DataService.get(player)
	if data == nil then
		return false, "Still loading your candy..."
	end
	local level = (data.upgrades :: any)[trackId] :: number
	local check, cost = Formulas.canBuy(trackId, level, data.rebirths, data.candy)
	if check == "maxed" then
		return false, "Already maxed out!"
	elseif check == "needsRebirth" then
		return false, `Rebirth {Formulas.rebirthsForLevel(trackId, level)} unlocks the next level`
	elseif check == "tooExpensive" then
		return false, `You need {Format.number((cost :: number) - data.candy)} more 🍬`
	end
	if not CandyService.spend(player, cost :: number) then
		return false, "Not enough candy"
	end
	DataService.mutate(player, "upgrades", function(upgrades)
		upgrades[trackId] = level + 1
	end)
	if trackId == "sneakers" then
		applyMovement(player)
	end
	return true, describe(trackId, level + 1)
end

function UpgradeService.Start()
	Net.handle("BuyUpgrade", function(player: Player, trackId: any)
		return UpgradeService.buy(player, trackId)
	end, { rate = 4, burst = 8 })

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			applyMovement(player)
		end)
		if player.Character then
			applyMovement(player)
		end
	end
	DataService.Loaded:Connect(function(player: Player)
		watch(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			watch(player)
		end
	end
	-- /reset and admin edits change levels without going through buy().
	DataService.Changed:Connect(function(player: Player, key: string)
		if key == "upgrades" then
			applyMovement(player)
		end
	end)
end

return UpgradeService
