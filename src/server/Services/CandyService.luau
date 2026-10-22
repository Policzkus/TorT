--!strict
-- The only place candy is created, carried, banked or spent. Everything goes through Formulas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Modules.Formulas)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local DataService = require(script.Parent.DataService)
local WorldEventsService = require(script.Parent.WorldEventsService)

local CandyService = {}

CandyService.Stashed = Signal.new() -- (player, moved: number, boxFull: boolean)

-- Summed bonus per category for door candy (PROMPT §3.7). Later phases add costumes, familiars,
-- party/friends, potions and passes here.
function CandyService.bonuses(player: Player): Formulas.Bonuses
	local data = DataService.get(player)
	if data == nil then
		return {}
	end
	return {
		charm = Formulas.charmBonus(data.upgrades.charm),
		rebirth = Formulas.rebirthBonus(data.rebirths),
	}
end

-- Product of active event multipliers (Witching Hour, Blood Moon), capped.
function CandyService.eventMultiplier(_player: Player): number
	return WorldEventsService.eventMultiplier()
end

function CandyService.bucketCapacity(player: Player): number
	local data = DataService.get(player)
	return if data then Formulas.bucketCapacity(data.upgrades.bucketTier) else 0
end

function CandyService.boxCapacity(player: Player): number
	local data = DataService.get(player)
	return if data then Formulas.boxCapacity(data.rebirths) else 0
end

-- Adds earned candy to the bucket. Returns (added, overflow).
function CandyService.addToBucket(player: Player, amount: number): (number, number)
	local data = DataService.get(player)
	if data == nil or amount <= 0 then
		return 0, 0
	end
	local bucket, added, overflow =
		Formulas.addToBucket(data.bucket, math.floor(amount), Formulas.bucketCapacity(data.upgrades.bucketTier))
	DataService.set(player, "bucket", bucket)
	if added > 0 then
		DataService.mutate(player, "stats", function(stats)
			stats.lifetimeCandy += added
		end)
	end
	return added, overflow
end

-- Pours the bucket into the Candy Box. Returns (moved, boxFull).
function CandyService.stash(player: Player): (number, boolean)
	local data = DataService.get(player)
	if data == nil then
		return 0, false
	end
	local capacity = Formulas.boxCapacity(data.rebirths)
	local moved, bucket, banked = Formulas.stash(data.bucket, data.candy, capacity)
	if moved > 0 then
		DataService.set(player, "bucket", bucket)
		DataService.set(player, "candy", banked)
	end
	local boxFull = banked >= capacity
	if moved > 0 then
		CandyService.Stashed:Fire(player, moved, boxFull)
	end
	return moved, boxFull
end

-- Caught! Removes `share` of the carried bucket (banked candy is never touched). Returns the loss.
function CandyService.loseFromBucket(player: Player, share: number): number
	local data = DataService.get(player)
	if data == nil or data.bucket <= 0 then
		return 0
	end
	local lost = math.floor(data.bucket * math.clamp(share, 0, 1))
	DataService.set(player, "bucket", data.bucket - lost)
	return lost
end

-- Spends banked candy. Returns false (and changes nothing) if the player can't afford it.
function CandyService.spend(player: Player, cost: number): boolean
	local data = DataService.get(player)
	if data == nil or cost < 0 or data.candy < cost then
		return false
	end
	DataService.set(player, "candy", data.candy - cost)
	return true
end

return CandyService
