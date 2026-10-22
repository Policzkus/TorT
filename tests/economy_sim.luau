--!strict
-- Economy simulator (PROMPT §3.14). Usage from the project root:  lune run tests/economy_sim [hours]
-- Models an average player on the real config: knock → mini-game grade → bucket → stash trips →
-- greedy shopping → gates → rebirth when the Candy Box is full. Prints a milestone timeline.
-- Deterministic (seeded) so tuning changes are comparable run to run.

local process = require("@lune/process")
local rbx = require("./lib/rbx")

local Formulas = rbx.require("src/shared/Modules/Formulas")
local Rng = rbx.require("src/shared/Modules/Rng")
local Economy = rbx.require("src/shared/Config/Economy")
local Neighborhoods = rbx.require("src/shared/Config/Neighborhoods")
local Upgrades = rbx.require("src/shared/Config/Upgrades")
local World = rbx.require("src/shared/Config/World")

local HOURS = tonumber(process.args[1]) or 8
local VERBOSE = process.args[2] == "-v"

-- Player model -------------------------------------------------------------------------------
local GRADE_ODDS = { MISS = 10, GOOD = 40, GREAT = 35, PERFECT = 15 }
local KNOCK_OVERHEAD = 0.8 -- walk up the path, prompt, small hesitation
local MINIGAME_TIME = 1.9 -- average seconds from knock to candy (tap + result)
local TELEPORT_TIME = 6
local STASH_TIME = 1.5
local SHOP_TIME = 4 -- per shopping visit (opening the menu, clicking)
local START_DELAY = 8 -- spawning, looking around, walking to the first house
local CROSS_STREET = World.HOUSE_SETBACK * 2

local rng = Rng.new(2026)

type House = { z: number, side: number, ready: number }

type State = {
	t: number,
	candy: number,
	bucket: number,
	rebirths: number,
	upgrades: { [string]: number },
	unlocked: number, -- highest neighborhood index unlocked
	zone: number, -- current neighborhood index
	z: number,
	side: number,
	houses: { House },
	purchases: { number },
}

local timeline: { string } = {}
local function clock(t: number): string
	local s = math.floor(t)
	return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end
local function mark(state: State, text: string)
	table.insert(timeline, string.format("%s  %s", clock(state.t), text))
end

local function streetLength(houses: number): number
	return World.ENTRANCE_MARGIN + math.ceil(houses / 2) * World.LOT_SPACING + World.END_MARGIN
end

local function buildHouses(index: number): { House }
	local n = Neighborhoods.list[index]
	local list = {}
	for i = 0, n.houses - 1 do
		local slot = i // 2
		local side = if i % 2 == 0 then -1 else 1
		local z = World.ENTRANCE_MARGIN + World.LOT_SPACING * (slot + 0.5) + (if side > 0 then 10 else 0)
		table.insert(list, { z = z, side = side, ready = 0 })
	end
	return list
end

local function speed(state: State): number
	return Formulas.walkSpeed(state.upgrades.sneakers)
end

local function capacity(state: State): number
	return Formulas.bucketCapacity(state.upgrades.bucketTier)
end

local function bonuses(state: State)
	return { charm = Formulas.charmBonus(state.upgrades.charm), rebirth = Formulas.rebirthBonus(state.rebirths) }
end

local function expectedDoor(state: State): number
	local n = Neighborhoods.list[state.zone]
	local base = (n.candy.min + n.candy.max) / 2
	return Formulas.doorCandy(base, "GOOD", 0, bonuses(state)) * 1.35
end

-- Where the time goes (seconds), for tuning.
local spent = { walking = 0, knocking = 0, waiting = 0, stashing = 0, shopping = 0, teleports = 0 }

local function travel(state: State, z: number, side: number)
	local distance = math.abs(state.z - z) + (if side ~= state.side then CROSS_STREET else 0)
	state.t += distance / speed(state)
	spent.walking += distance / speed(state)
	state.z, state.side = z, side
end

local firsts: { [string]: boolean } = {}
local function first(state: State, key: string, text: string)
	if not firsts[key] then
		firsts[key] = true
		mark(state, text)
	end
end

local function enterZone(state: State, index: number)
	state.zone = index
	state.houses = buildHouses(index)
	state.z, state.side = 0, 1
end

-- Greedy shopping: unlock the next gate as soon as possible; otherwise buy the cheapest
-- affordable upgrade as long as it doesn't eat too much of the savings for that gate.
local function shop(state: State)
	local spentAny = false
	while true do
		local nextIndex = state.unlocked + 1
		local nextHood = Neighborhoods.list[nextIndex]
		if nextHood and nextHood.unlock.rebirths <= state.rebirths and state.candy >= nextHood.unlock.price then
			state.candy -= nextHood.unlock.price
			state.unlocked = nextIndex
			mark(state, `🔓 unlocked {nextHood.name} ({nextHood.unlock.price})`)
			table.insert(state.purchases, state.t)
			state.t += TELEPORT_TIME
			spent.teleports += TELEPORT_TIME
			enterZone(state, nextIndex)
			spentAny = true
			continue
		end
		local gatePrice = if nextHood and nextHood.unlock.rebirths <= state.rebirths
			then nextHood.unlock.price
			else math.huge
		local bestTrack, bestCost = nil, math.huge
		for _, trackId in Upgrades.ORDER do
			local check, cost = Formulas.canBuy(trackId, state.upgrades[trackId], state.rebirths, state.candy)
			if check == "ok" and cost and cost < bestCost and cost <= math.max(gatePrice * 0.45, 0) then
				bestTrack, bestCost = trackId, cost
			end
		end
		if bestTrack == nil then
			break
		end
		state.candy -= bestCost
		state.upgrades[bestTrack] += 1
		table.insert(state.purchases, state.t)
		first(state, "upgrade", `first upgrade: {bestTrack} ({bestCost})`)
		if VERBOSE then
			mark(
				state,
				`  bought {bestTrack} -> {state.upgrades[bestTrack]} ({bestCost}), banked {math.floor(state.candy)}`
			)
		end
		if bestTrack == "bucketTier" then
			mark(state, `🪣 {Formulas.bucketTier(state.upgrades.bucketTier).name} ({bestCost})`)
		end
		spentAny = true
	end
	if spentAny then
		state.t += SHOP_TIME
		spent.shopping += SHOP_TIME
	end
end

local function rebirth(state: State)
	state.rebirths += 1
	state.candy, state.bucket = 0, 0
	state.upgrades = { bucketTier = 1, charm = 0, sneakers = 0 }
	mark(state, `☠ REBIRTH {state.rebirths} (box was full)`)
	state.t += 10
	-- Go to the best unlocked street.
	enterZone(state, state.unlocked)
end

local function stash(state: State)
	-- Drop-offs sit at the entrance, the middle and the end of every street (World/Street).
	local length = streetLength(Neighborhoods.list[state.zone].houses)
	local dropZ = math.round(state.z / (length / 2)) * (length / 2)
	travel(state, dropZ, state.side)
	local moved, bucket, banked = Formulas.stash(state.bucket, state.candy, Formulas.boxCapacity(state.rebirths))
	state.bucket, state.candy = bucket, banked
	state.t += STASH_TIME
	spent.stashing += STASH_TIME
	first(state, "stash", `first stash ({moved})`)
	if state.candy >= Formulas.boxCapacity(state.rebirths) then
		rebirth(state)
		return
	end
	shop(state)
end

local function knock(state: State, house: House)
	travel(state, house.z, house.side)
	state.t += KNOCK_OVERHEAD + MINIGAME_TIME
	spent.knocking += KNOCK_OVERHEAD + MINIGAME_TIME
	local n = Neighborhoods.list[state.zone]
	local base = n.candy.min + rng:next() * (n.candy.max - n.candy.min)
	local grade = rng:weighted(GRADE_ODDS) :: string
	local amount = Formulas.doorCandy(base, grade, 0, bonuses(state))
	local bucket, _, overflow = Formulas.addToBucket(state.bucket, amount, capacity(state))
	state.bucket = bucket
	house.ready = state.t + Economy.DOOR_COOLDOWN
	first(state, "candy", `first candy (+{amount})`)
	if overflow > 0 then
		first(state, "overflow", "first overflow")
	end
end

local function nextHouse(state: State): House?
	local best, bestCost = nil, math.huge
	for _, house in state.houses do
		if house.ready <= state.t then
			local cost = math.abs(house.z - state.z) + (if house.side ~= state.side then CROSS_STREET else 0)
			if cost < bestCost then
				best, bestCost = house, cost
			end
		end
	end
	return best
end

local state: State = {
	t = START_DELAY,
	candy = 0,
	bucket = 0,
	rebirths = 0,
	upgrades = { bucketTier = 1, charm = 0, sneakers = 0 },
	unlocked = 1,
	zone = 1,
	z = 0,
	side = 1,
	houses = buildHouses(1),
	purchases = {},
}

local doors = 0
while state.t < HOURS * 3600 do
	if state.bucket > 0 and state.bucket + expectedDoor(state) * 0.5 >= capacity(state) then
		stash(state)
		continue
	end
	local house = nextHouse(state)
	if house then
		knock(state, house)
		doors += 1
	else
		-- Nothing ready: bank what we carry while we wait.
		if state.bucket > 0 then
			stash(state)
		end
		local soonest = math.huge
		for _, h in state.houses do
			soonest = math.min(soonest, h.ready)
		end
		spent.waiting += math.max(0, soonest - state.t)
		state.t = math.max(state.t, soonest)
	end
	if state.rebirths >= 6 then
		break
	end
end

-- Longest stretch without buying anything during the first hour.
local longestGap, previous = 0, START_DELAY
for _, at in state.purchases do
	if at > 3600 then
		break
	end
	longestGap = math.max(longestGap, at - previous)
	previous = at
end

print(table.concat(timeline, "\n"))
print(string.format("\n%d doors in %s (%.1f per minute).", doors, clock(state.t), doors / state.t * 60))
local breakdown = {}
for _, key in { "knocking", "walking", "waiting", "stashing", "shopping", "teleports" } do
	table.insert(breakdown, string.format("%s %d%%", key, math.round(spent[key] / state.t * 100)))
end
print("Time: " .. table.concat(breakdown, " · "))
print(string.format("Longest gap between purchases in the first hour: %s (target ≤ ~3:00)", clock(longestGap)))
print("Targets: first stash 1:00 · first upgrade ≤ 2:00 · Maple Lane 5–7 min · Pumpkin Hollow 20–25 min ·")
print("         first Rebirth 45–60 min · Rebirth 3 ~3 h · Rebirth 5 ~7–8 h")
