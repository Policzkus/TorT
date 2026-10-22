--!strict
-- Pure economy math shared by the server, the client UI and the Lune tests. No Roblox APIs.
-- Rule (PROMPT §3.7): bonuses ADD within a category and MULTIPLY across categories.

local Config = script.Parent.Parent.Config
local Economy = require(Config.Economy)
local Upgrades = require(Config.Upgrades)

-- Summed bonus per category, e.g. { charm = 0.3 } = +30% charm. Missing categories count as 0.
export type Bonuses = { [string]: number }

local Formulas = {}

function Formulas.gradeMultiplier(grade: string): number
	local multiplier = Economy.GRADE_MULTIPLIER[grade]
	assert(multiplier, `Unknown grade '{grade}'`)
	return multiplier
end

function Formulas.isGoodGrade(grade: string): boolean
	return grade == "GREAT" or grade == "PERFECT"
end

-- Sweet Streak bonus for `count` consecutive GREAT/PERFECT doors.
function Formulas.streakBonus(count: number): number
	return math.min(count * Economy.STREAK_STEP, Economy.STREAK_MAX)
end

function Formulas.rebirthBonus(rebirths: number): number
	return Economy.REBIRTH_BONUS * rebirths
end

-- Candy from one door. `base` is the rolled neighborhood amount × house-type multiplier.
-- `eventMultiplier` is the product of active events (Witching Hour ×2, Blood Moon ×2…), capped.
function Formulas.doorCandy(
	base: number,
	grade: string,
	streakBonus: number,
	bonuses: Bonuses,
	eventMultiplier: number?
): number
	local total = base * Formulas.gradeMultiplier(grade) * (1 + streakBonus)
	for _, bonus in bonuses do
		total *= 1 + bonus
	end
	total *= math.clamp(eventMultiplier or 1, 1, Economy.EVENT_MULTIPLIER_CAP)
	return math.max(Economy.MIN_DOOR_CANDY, math.round(total))
end

-- Bucket ------------------------------------------------------------------------------------

local bucketTiers = Upgrades.tracks.bucketTier.tiers :: { Upgrades.Tier }

function Formulas.bucketTier(tier: number): Upgrades.Tier
	return bucketTiers[math.clamp(tier, 1, #bucketTiers)]
end

function Formulas.bucketCapacity(tier: number, bonus: number?): number
	return math.floor(Formulas.bucketTier(tier).capacity * (1 + (bonus or 0)))
end

-- Adds candy to a bucket. Anything above capacity is lost (that's the push to stash).
-- Returns newBucket, added, overflow.
function Formulas.addToBucket(bucket: number, amount: number, capacity: number): (number, number, number)
	local space = math.max(0, capacity - bucket)
	local added = math.min(amount, space)
	return bucket + added, added, amount - added
end

-- Candy Box ---------------------------------------------------------------------------------

function Formulas.boxCapacity(rebirths: number): number
	local list = Economy.BOX_CAPACITY
	if rebirths < #list then
		return list[rebirths + 1]
	end
	return list[#list] * Economy.BOX_GROWTH ^ (rebirths - #list + 1)
end

-- How much of the bucket fits in the box. Returns moved, newBucket, newBanked.
function Formulas.stash(bucket: number, banked: number, boxCapacity: number): (number, number, number)
	local moved = math.max(0, math.min(bucket, boxCapacity - banked))
	return moved, bucket - moved, banked + moved
end

-- Upgrades ----------------------------------------------------------------------------------

function Formulas.track(trackId: string): Upgrades.Track
	local track = Upgrades.tracks[trackId]
	assert(track, `Unknown upgrade track '{trackId}'`)
	return track
end

-- Highest level the player may own in this life.
function Formulas.maxLevel(trackId: string, rebirths: number): number
	local track = Formulas.track(trackId)
	if track.kind == "tiers" then
		local best = 1
		for index, tier in track.tiers :: { Upgrades.Tier } do
			if tier.rebirths <= rebirths then
				best = index
			end
		end
		return best
	end
	return (track.maxLevel :: number) + (track.maxPerRebirth or 0) * rebirths
end

-- Highest level that exists at all (ignoring rebirth gates). nil = unbounded.
function Formulas.absoluteMaxLevel(trackId: string): number?
	local track = Formulas.track(trackId)
	if track.kind == "tiers" then
		return #(track.tiers :: { Upgrades.Tier })
	end
	if (track.maxPerRebirth or 0) == 0 then
		return track.maxLevel
	end
	return nil
end

-- Price of going from `level` to `level + 1`, or nil if that level doesn't exist.
function Formulas.upgradeCost(trackId: string, level: number): number?
	local track = Formulas.track(trackId)
	if track.kind == "tiers" then
		local nextTier = (track.tiers :: { Upgrades.Tier })[level + 1]
		return if nextTier then nextTier.cost else nil
	end
	return math.round((track.baseCost :: number) * (track.growth :: number) ^ level)
end

-- Rebirths needed before `level + 1` can be bought.
function Formulas.rebirthsForLevel(trackId: string, level: number): number
	local track = Formulas.track(trackId)
	if track.kind == "tiers" then
		local nextTier = (track.tiers :: { Upgrades.Tier })[level + 1]
		return if nextTier then nextTier.rebirths else math.huge
	end
	local perRebirth = track.maxPerRebirth or 0
	local base = track.maxLevel :: number
	if level < base then
		return 0
	end
	if perRebirth == 0 then
		return math.huge
	end
	return math.floor((level - base) / perRebirth) + 1
end

export type BuyCheck = "ok" | "maxed" | "needsRebirth" | "tooExpensive"

function Formulas.canBuy(trackId: string, level: number, rebirths: number, candy: number): (BuyCheck, number?)
	local cost = Formulas.upgradeCost(trackId, level)
	local absoluteMax = Formulas.absoluteMaxLevel(trackId)
	if cost == nil or (absoluteMax ~= nil and level >= absoluteMax) then
		return "maxed", nil
	end
	if level >= Formulas.maxLevel(trackId, rebirths) then
		return "needsRebirth", cost
	end
	if candy < cost then
		return "tooExpensive", cost
	end
	return "ok", cost
end

function Formulas.charmBonus(level: number): number
	return (Formulas.track("charm").perLevel :: number) * level
end

function Formulas.walkSpeed(level: number): number
	local track = Formulas.track("sneakers")
	return (track.baseValue :: number) + (track.perLevel :: number) * level
end

return Formulas
